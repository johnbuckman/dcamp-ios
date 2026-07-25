import SwiftUI
import UIKit

/// Build a Color that resolves differently in light vs dark (matches dcamp.css's
/// :root vs :root[data-theme=dark] palette).
private func dcDynamic(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
    Color(UIColor { tc in
        let c = tc.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    })
}

// Design tokens mirrored from dcamp's dcamp.css. Light is warm "paper"; the dark
// palette mirrors :root[data-theme=dark] (warm-dark panels, softer accent #2c8a54).
extension Color {
    static let dcBg         = dcDynamic((0.992, 0.976, 0.953), (0.102, 0.090, 0.075)) // #fdf9f3 / #1a1712
    static let dcPanel      = dcDynamic((1.000, 1.000, 1.000), (0.141, 0.125, 0.102)) // #ffffff / #24201a
    static let dcInk        = dcDynamic((0.110, 0.110, 0.110), (0.949, 0.937, 0.914)) // #1c1c1c / #f2efe9
    static let dcInkSoft    = dcDynamic((0.420, 0.420, 0.420), (0.722, 0.698, 0.659)) // #6b6b6b / #b8b2a8
    static let dcMuted      = dcDynamic((0.541, 0.522, 0.475), (0.588, 0.561, 0.510)) // #8a8579 / #968f82
    static let dcLine       = dcDynamic((0.925, 0.902, 0.859), (0.200, 0.184, 0.157)) // #ece6db / #332f28
    static let dcLineStrong = dcDynamic((0.867, 0.835, 0.780), (0.278, 0.255, 0.216)) // #ddd5c7 / #474137
    static let dcAccent     = dcDynamic((0.086, 0.639, 0.290), (0.173, 0.541, 0.329)) // #16a34a / #2c8a54
    static let dcAccentInk  = dcDynamic((0.059, 0.478, 0.216), (0.376, 0.784, 0.529)) // #0f7a37 / #60c887
    static let dcLink       = dcDynamic((0.122, 0.435, 0.839), (0.400, 0.639, 0.925)) // #1f6fd6 / #66a3ec
    // Elements that always carry white text, so they must stay dark in BOTH modes:
    static let dcDecentBg   = dcDynamic((0.110, 0.110, 0.110), (0.302, 0.278, 0.235)) // DECENT pill
    // Others' DM bubble — light grey / warm dark-grey (dcInk text stays readable on both):
    static let dcBubbleOther = dcDynamic((0.941, 0.929, 0.898), (0.216, 0.196, 0.165))
}

/// User-selectable appearance. Persisted locally in @AppStorage("dcamp_theme") and
/// synced to the server as the web's `dcamp_theme` ui-pref ("" == system).
enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    /// Value sent to `ui_prefs_save` (matches the web: empty string for system).
    var serverValue: String { self == .system ? "" : rawValue }
    /// Normalize a server/bootstrap value into a mode ("" / unknown → system).
    static func from(_ raw: String?) -> ThemeMode {
        switch raw { case "light": return .light; case "dark": return .dark; default: return .system }
    }
}

enum DC {
    static let radius: CGFloat = 14
    static let maxContentWidth: CGFloat = 900   // centered column like the web
}

// MARK: - Card

extension View {
    /// White rounded panel with dcamp's warm border + soft shadow.
    func dcCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(Color.dcPanel)
            .clipShape(RoundedRectangle(cornerRadius: DC.radius))
            .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(Color.dcLine, lineWidth: 1))
            .shadow(color: Color(red: 0.16, green: 0.12, blue: 0.04).opacity(0.05), radius: 10, x: 0, y: 4)
    }

    /// Constrain to the centered content column used across the app.
    func dcColumn() -> some View {
        frame(maxWidth: DC.maxContentWidth).frame(maxWidth: .infinity)
    }
}

// MARK: - Badges

/// Green outlined pill: machine + "since YEAR" (dcamp's .owner-badge).
struct MachineBadge: View {
    let person: Person?
    var body: some View {
        if let p = person, let m = p.machine, !m.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 8))
                Text(p.since.map { "\(m) since \($0)" } ?? m).lineLimit(1)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.dcAccentInk)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Color.dcPanel, in: Capsule())
            .overlay(Capsule().stroke(Color.dcLineStrong, lineWidth: 1))
        }
    }
}

/// Wrapping row layout so an author line (name + badges + date) flows onto
/// multiple lines on narrow screens instead of squashing.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxLineW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { maxLineW = max(maxLineW, x - hSpacing); x = 0; y += lineH + vSpacing; lineH = 0 }
            x += s.width + hSpacing; lineH = max(lineH, s.height)
        }
        maxLineW = max(maxLineW, x - hSpacing)
        return CGSize(width: min(maxLineW, maxW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += lineH + vSpacing; lineH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + hSpacing; lineH = max(lineH, s.height)
        }
    }
}

/// Dark "DECENT" pill (dcamp's .decent-badge).
struct DecentBadge: View {
    let person: Person?
    var body: some View {
        if person?.decent == true {
            Text("DECENT")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 1.5)
                .background(Color.dcDecentBg, in: Capsule())
        }
    }
}

/// Author line used on posts/comments/chat: name + DECENT + machine + date.
struct AuthorLine: View {
    let person: Person?
    var date: Int? = nil
    var tappable: Bool = true
    @Environment(Router.self) private var router

    var body: some View {
        FlowLayout(hSpacing: 8, vSpacing: 5) {
            Text(person?.name ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.dcInkSoft)
                .fixedSize()
                .onTapGesture { if tappable, let id = person?.id { router.personID = id } }
            DecentBadge(person: person)
            MachineBadge(person: person)
            if let date {
                Text("· \(RelativeTime.string(date))")
                    .font(.system(size: 13)).foregroundStyle(Color.dcMuted).fixedSize()
            }
        }
    }
}

// MARK: - Small building blocks

/// Uppercase muted section label ("OTHER", "Forums").
struct DCSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold)).tracking(0.5)
            .foregroundStyle(Color.dcMuted)
    }
}

/// Green primary button used app-wide (Continue, Send, New message, Summarize).
struct DCPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.dcAccent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Rounded outline pill toggle used for forum filters (Popular / I posted / …).
struct DCFilterPill: View {
    let icon: String
    let title: String
    var active: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? Color.dcAccentInk : Color.dcInkSoft)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(active ? Color.dcAccent.opacity(0.12) : Color.dcPanel, in: Capsule())
            .overlay(Capsule().stroke(active ? Color.dcAccent.opacity(0.5) : Color.dcLineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
