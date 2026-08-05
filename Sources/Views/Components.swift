import SwiftUI

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
        .onTapGesture { if tappable, let id = person?.id, id > 0 { router?.personID = id } }
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
