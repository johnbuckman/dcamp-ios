import SwiftUI

/// In-app Help — a native rendering of dcamp's member-facing Help page (the
/// 14-section feature taxonomy). Admin-only features are deliberately excluded.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(HelpContent.sections) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: s.icon).foregroundStyle(Color.dcAccent)
                                Text(s.title).font(.system(size: 19, weight: .heavy)).foregroundStyle(Color.dcInk)
                            }
                            ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(Color.dcMuted)
                                    Text(p).font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().background(Color.dcLine)
                    }
                }
                .padding(18)
                .dcColumn()
            }
            .background(Color.dcBg).scrollContentBackground(.hidden)
            .navigationTitle(T("Help")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(T("Done")) { dismiss() } } }
        }
    }
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let points: [String]
}

private enum HelpContent {
    static let sections: [HelpSection] = [
        HelpSection(icon: "bubble.left.and.bubble.right.fill", title: "Forums", points: [
            "Each forum holds threads. Tap a forum to see its threads, newest activity first.",
            "Filter by Popular, I posted, I commented, or I’m mentioned.",
            "The Problems board tracks issues with an Unsolved / Solved / Closed status.",
            "Posts get auto-categorised, and problem-like posts may be moved to Problems.",
        ]),
        HelpSection(icon: "square.and.pencil", title: "Writing posts", points: [
            "Rich text with colour and highlight, plus @mentions of people (and bots).",
            "Attach images by picking from your library; tap an image to view it full-size.",
            "Type Markdown as you go: # headings, - lists, > quotes, **bold**, *italic*, ``` code.",
            "Quote & reply keeps the original author’s attribution.",
            "Drafts are kept per thread, and ⌘↵ sends.",
        ]),
        HelpSection(icon: "hand.thumbsup.fill", title: "Reactions", points: [
            "React to any message or comment with an emoji. Tap a reaction to add or remove yours.",
            "Chat lines and direct messages don’t have reactions.",
        ]),
        HelpSection(icon: "text.bubble.fill", title: "Chat", points: [
            "The Chat Room is a live, flat conversation for Decent owners.",
            "Post rich text and @mention people or the AI assistants.",
            "Use “Link to this” to copy a link to any chat line.",
        ]),
        HelpSection(icon: "envelope.fill", title: "Direct messages", points: [
            "Private one-to-one or group conversations, shown as chat bubbles.",
            "Add or remove people; archived conversations return when there’s new activity.",
            "Unread counts show which conversations have new messages.",
        ]),
        HelpSection(icon: "sparkles", title: "AI assistants", points: [
            "@mention Derek or DeepSeek in any thread, comment, chat line, or a 1:1 DM.",
            "They draw on the whole forum and reply in your language; answers stream in.",
            "When you start a question-like post, Derek may already have an answer to show you.",
        ]),
        HelpSection(icon: "magnifyingglass", title: "Search", points: [
            "Search threads, comments, chat, your DMs, and people.",
            "Filter by type and forum, sort by relevance or newest, and keep only the best matches.",
            "“Experts only” narrows people to recognised experts.",
            "Ask Derek for an AI answer drawn from the whole forum.",
        ]),
        HelpSection(icon: "shield.lefthalf.filled", title: "People & privacy", points: [
            "Open anyone’s card to see their activity, machine, and a Message button.",
            "Mute someone to hide their messages, comments, chat and DMs, and stop their notifications.",
            "Report someone to the moderators.",
        ]),
        HelpSection(icon: "sparkles.rectangle.stack", title: "Summaries", points: [
            "Tap ✨ Summarize on the home, a forum, a thread, or chat for an AI digest.",
            "Choose how far back — since your last visit or a number of days.",
            "The home summary highlights where you were mentioned.",
            "Get summaries by email daily, weekly, or monthly, and email yourself a sample.",
        ]),
        HelpSection(icon: "globe", title: "Languages", points: [
            "Content is shown in your language automatically.",
            "Tap “Show original text” on any post to see what was originally written.",
        ]),
        HelpSection(icon: "person.crop.circle", title: "Your account", points: [
            "Set your name, about, picture, and location (and whether it shows on your card).",
            "Choose which notifications you get as pop-ups or email.",
            "Manage muted people, your Basecamp link, appearance (light/dark), and closing your account.",
        ]),
    ]
}
