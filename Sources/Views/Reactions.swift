import SwiftUI

/// Reaction (boost) row: existing emoji reactions with counts + an add button.
/// Tapping an existing one toggles the viewer's reaction; "+" opens the picker.
/// `onChange` should re-fetch the parent so counts refresh.
struct BoostBar: View {
    let type: String        // "message" | "comment" | "chat"
    let id: Int
    let boosts: Boosts
    var onChange: () async -> Void

    @State private var picking = false
    private let api = DcampAPI.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(boosts.list) { b in
                Button { toggle(b.content) } label: {
                    HStack(spacing: 3) {
                        Text(b.display).font(.system(size: 14))
                        // Web always renders the count (<span class="n">) — show it even at 1.
                        Text("\(b.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dcInkSoft)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(b.content == boosts.mine ? Color.dcAccent.opacity(0.15) : Color.dcPanel, in: Capsule())
                    .overlay(Capsule().stroke(b.content == boosts.mine ? Color.dcAccent.opacity(0.5) : Color.dcLineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button { picking = true } label: {
                Image(systemName: "face.smiling").font(.system(size: 13))
                    .foregroundStyle(Color.dcMuted)
                    .padding(5)
                    .background(Color.dcPanel, in: Circle())
                    .overlay(Circle().stroke(Color.dcLineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        // Anchored popover (like the web's pickEmoji), NOT a sheet — on Mac Catalyst
        // the sheet's Cancel didn't respond until the mouse moved. A popover dismisses
        // on outside tap, so there's no Cancel button to get stuck.
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            EmojiPicker { emoji in picking = false; toggle(emoji) }
                .presentationCompactAdaptation(.popover)
        }
    }

    private func toggle(_ content: String) {
        Task { await api.boostToggle(type: type, id: id, content: content); await onChange() }
    }
}

/// Emoji reaction picker — mirrors the web's designed picker (`pickEmoji`): a search
/// field over category-grouped emoji, in an anchored popover. Searching flattens to
/// keyword-matched results; otherwise the categories are browsable (Boosts first,
/// espresso/tea leading the food group), matching `window.DCAMP_EMOJI`.
struct EmojiPicker: View {
    var onPick: (String) -> Void
    @State private var query = ""

    // (emoji, search keywords) grouped by category. Boosts = the web's quick favourites.
    @MainActor private static var categories: [(String, [(String, String)])] {
        [
        (T("Boosts"), [("👍","thumbs up like yes good"),("🎉","party tada celebrate"),("❤️","heart love"),("😄","smile happy"),("🙏","thanks pray please"),("🔥","fire hot lit"),("👀","eyes look watching"),("🚀","rocket launch ship"),("💯","hundred perfect"),("😮","wow surprised"),("👏","clap applause"),("✅","check done yes"),("🙌","raise hands praise"),("💪","strong muscle")]),
        (T("Smileys"), [("😀","grin happy"),("😊","blush smile"),("🙂","slight smile"),("😉","wink"),("😍","heart eyes love"),("🥰","adore love"),("😎","cool sunglasses"),("🤩","star struck"),("🤔","thinking hmm"),("😅","sweat laugh"),("😂","laugh cry"),("🤣","rofl"),("🙃","upside down"),("😴","sleep tired"),("😢","sad cry"),("😭","sob cry"),("🥳","party celebrate"),("🤯","mind blown"),("🫠","melting"),("🤗","hug")]),
        (T("Gestures"), [("👎","thumbs down no"),("👌","ok perfect"),("✌️","peace victory"),("🤙","call shaka"),("🤞","fingers crossed hope"),("👋","wave hi bye"),("🤝","handshake deal"),("👉","point"),("✍️","write note")]),
        (T("Coffee & food"), [("☕","coffee espresso"),("🍵","tea matcha"),("🫖","teapot"),("🧊","ice cold"),("🍫","chocolate"),("🍩","donut"),("🥛","milk"),("🍪","cookie"),("🧁","cupcake"),("🥐","croissant")]),
        (T("Objects"), [("⭐️","star favorite"),("⚡️","lightning fast power"),("💡","idea bulb"),("🧠","brain smart"),("📈","chart up growth"),("🛠️","tools fix"),("🧪","test experiment"),("🎯","target goal"),("🥇","gold medal first"),("🔧","wrench fix"),("⚙️","gear settings"),("🔋","battery power")]),
        (T("Symbols"), [("❌","x no wrong"),("❓","question"),("❗","exclaim important"),("➕","plus add"),("♻️","recycle"),("⚠️","warning"),("🔔","bell notify"),("💬","comment chat"),("🏆","trophy win")]),
        ]
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [String] = []
        for (_, items) in Self.categories {
            for (e, kw) in items where kw.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { out.append(e) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Color.dcMuted)
                TextField(T("Search emoji"), text: $query).textFieldStyle(.plain).font(.system(size: 15))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.categories, id: \.0) { name, items in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.dcMuted)
                                LazyVGrid(columns: cols, spacing: 6) {
                                    ForEach(items, id: \.0) { e, _ in emojiButton(e) }
                                }
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(matches, id: \.self) { emojiButton($0) }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320, height: 380)
        .background(Color.dcBg)
    }

    private func emojiButton(_ e: String) -> some View {
        Button { onPick(e) } label: {
            Text(e).font(.system(size: 24)).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}
