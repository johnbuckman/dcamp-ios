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
        .sheet(isPresented: $picking) {
            EmojiPicker { emoji in picking = false; toggle(emoji) }
        }
    }

    private func toggle(_ content: String) {
        Task { await api.boostToggle(type: type, id: id, content: content); await onChange() }
    }
}

/// A compact emoji picker (curated common reactions + a few categories).
struct EmojiPicker: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let emojis: [String] = [
        "👍","❤️","😂","🎉","🙌","🔥","👏","💯","😍","🤔","😮","😢",
        "🙏","☕️","👌","✅","💪","🚀","⭐️","😅","😉","🤩","🥰","😎",
        "👀","🤯","😴","🤤","🫠","🤗","🙃","😬","🤙","✌️","🤝","💡",
        "☕","🫖","⚡️","🧠","📈","🛠️","🧪","🎯","🥇","🍫","🍩","🧊",
    ]
    private let cols = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(emojis, id: \.self) { e in
                        Button { onPick(e); dismiss() } label: { Text(e).font(.system(size: 30)) }
                    }
                }
                .padding()
            }
            .background(Color.dcBg)
            .navigationTitle("React").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
