import SwiftUI

// Design tokens mirrored from dcamp's dcamp.css :root. The web app is light-only
// and warm ("paper"), so we use fixed colors and force light appearance to match.
extension Color {
    static let dcBg         = Color(red: 0.992, green: 0.976, blue: 0.953) // #fdf9f3 warm paper
    static let dcPanel      = Color.white                                    // #ffffff
    static let dcInk        = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1c1c1c
    static let dcInkSoft    = Color(red: 0.420, green: 0.420, blue: 0.420)  // #6b6b6b
    static let dcMuted      = Color(red: 0.541, green: 0.522, blue: 0.475)  // #8a8579
    static let dcLine       = Color(red: 0.925, green: 0.902, blue: 0.859)  // #ece6db
    static let dcLineStrong = Color(red: 0.867, green: 0.835, blue: 0.780)  // #ddd5c7
    static let dcAccent     = Color(red: 0.086, green: 0.639, blue: 0.290)  // #16a34a green
    static let dcAccentInk  = Color(red: 0.059, green: 0.478, blue: 0.216)  // #0f7a37
    static let dcLink       = Color(red: 0.122, green: 0.435, blue: 0.839)  // #1f6fd6
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
                .background(Color.dcInk, in: Capsule())
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
