import SwiftUI

/// Notification inbox (unread items from `notif_poll`). Tapping an item marks it
/// seen and opens the target thread via `onOpen`.
struct NotificationsView: View {
    let store: NotificationsStore
    var onOpen: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView("You’re all caught up",
                                           systemImage: "bell.slash",
                                           description: Text("New mentions, replies and messages will appear here."))
                } else {
                    List(store.items) { notif in
                        Button { open(notif) } label: { NotifRow(notif: notif) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.items.isEmpty {
                        Button("Mark all read") { Task { await store.markAllSeen() } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func open(_ notif: Notif) {
        Task { await store.markSeen([notif.id]) }
        if let mid = DcampRoute.messageID(from: notif.route) {
            dismiss()
            onOpen(mid)
        }
    }
}

struct NotifRow: View {
    let notif: Notif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(person: notif.actor, size: 40)
                Image(systemName: notif.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.accentColor, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                (Text(notif.actor?.name ?? "Someone").fontWeight(.semibold)
                 + Text(" \(notif.kindLabel)").foregroundColor(.secondary))
                    .font(.subheadline)
                if let preview = notif.preview, !preview.isEmpty {
                    Text(PlainText.strip(preview))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(RelativeTime.string(notif.createdAt))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Cheap HTML→text for notification previews.
enum PlainText {
    static func strip(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = Inline.decodeEntities(s)
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Toolbar bell with an unread count badge.
struct NotificationsBell: View {
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count > 0 ? "bell.badge" : "bell")
                    .symbolRenderingMode(count > 0 ? .multicolor : .monochrome)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
        }
        .accessibilityLabel(count > 0 ? "Notifications, \(count) unread" : "Notifications")
    }
}
