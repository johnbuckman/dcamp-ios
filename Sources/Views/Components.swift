import SwiftUI
import LinkPresentation

// MARK: - Color from "#rrggbb"

extension Color {
    init?(hex: String?) {
        guard var s = hex, !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Relative time from Unix epoch seconds

enum RelativeTime {
    private static let fmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func string(_ epoch: Int?) -> String {
        guard let e = epoch, e > 0 else { return "" }
        return fmt.localizedString(for: Date(timeIntervalSince1970: TimeInterval(e)), relativeTo: Date())
    }
}

// MARK: - Avatar

struct Avatar: View {
    let person: Person?
    var size: CGFloat = 36
    var tappable: Bool = false            // tap → open that person's member card
    // Optional so avatars in contexts without a Router (e.g. some sheets) don't crash.
    @Environment(Router.self) private var router: Router?

    var body: some View {
        Group {
            if let url = person?.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().interpolation(.high).antialiased(true).scaledToFill()
                    default: initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        // Only attach a tap gesture when this avatar is meant to be tappable. An
        // always-present onTapGesture (even with a no-op body) still consumes the
        // tap, which swallowed the enclosing button — e.g. the top-bar avatar's
        // "open Settings" button never fired.
        .modifier(TapToOpenPerson(enabled: tappable, personID: person?.id, router: router))
    }

    private var initialsCircle: some View {
        ZStack {
            (Color(hex: person?.avatarColor) ?? .gray)
            Text(person?.initials ?? "?")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Attaches a "tap → open this person's card" gesture ONLY when enabled, so a
/// non-tappable avatar doesn't swallow taps meant for an enclosing button.
private struct TapToOpenPerson: ViewModifier {
    let enabled: Bool
    let personID: Int?
    let router: Router?
    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture { if let id = personID, id > 0 { router?.personID = id } }
        } else {
            content
        }
    }
}

// MARK: - Share sheet anchored to a ⋯ menu (iPad/Mac-safe replacement for ShareLink-in-Menu)

/// A `ShareLink` inside a `Menu` breaks on iPad/Mac: the menu dismisses, the ShareLink's
/// source view goes away, and UIKit anchors the share popover to a fallback spot → an empty
/// bubble under the nav-bar title. Instead, the menu holds one of these: its `view` is a
/// real UIView sitting behind the ⋯ label (via `ShareAnchorView`), and `share` presents a
/// `UIActivityViewController` from the top-most VC with its popover pointing at that view
/// once the menu has finished dismissing. On iPhone it's an ordinary sheet.
@MainActor final class ShareAnchor {
    weak var view: UIView?

    func share(url: URL, title: String) {
        // Let the context menu finish its dismissal animation first; presenting during it
        // is dropped ("already presenting") or loses the popover source.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.present(url: url, title: title)
        }
    }

    private func present(url: URL, title: String) {
        let window = view?.window
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }

        let avc = UIActivityViewController(activityItems: [ShareLinkItem(url: url, title: title)],
                                           applicationActivities: nil)
        if let pop = avc.popoverPresentationController {
            if let v = view, v.window != nil {
                pop.sourceView = v
                pop.sourceRect = v.bounds
            } else {   // anchor gone (shouldn't happen) — centre of the window, no arrow
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
        }
        top.present(avc, animated: true)
    }
}

/// Invisible UIView placed behind a menu label so `ShareAnchor` has a real popover source.
struct ShareAnchorView: UIViewRepresentable {
    let anchor: ShareAnchor
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        anchor.view = v
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { anchor.view = uiView }
}

/// A `Menu` whose content gets a `ShareAnchor` bound to the menu's own label.
struct AnchoredMenu<Content: View, Lbl: View>: View {
    @State private var anchor = ShareAnchor()
    @ViewBuilder var content: (ShareAnchor) -> Content
    @ViewBuilder var label: () -> Lbl
    var body: some View {
        Menu { content(anchor) } label: { label() }
            .background(ShareAnchorView(anchor: anchor))
    }
}

/// The shared URL, with the thread subject / "Comment — Author" as the link-preview title.
final class ShareLinkItem: NSObject, UIActivityItemSource {
    let url: URL, title: String
    init(url: URL, title: String) { self.url = url; self.title = title }
    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { url }
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ c: UIActivityViewController, subjectForActivityType t: UIActivity.ActivityType?) -> String { title }
    func activityViewControllerLinkMetadata(_ c: UIActivityViewController) -> LPLinkMetadata? {
        let md = LPLinkMetadata()
        md.originalURL = url
        md.url = url
        md.title = title
        if let img = UIImage(named: "DcampMark") { md.iconProvider = NSItemProvider(object: img) }
        return md
    }
}
