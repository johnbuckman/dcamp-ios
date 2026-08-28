import SwiftUI

/// Localized notification-kind label (the model's `kindLabel` is English-only and,
/// living outside the Views layer, isn't registered for translation). Kept here so
/// the phrases land in `UIStringCatalog`.
@MainActor func notifKindLabel(_ notif: Notif) -> String {
    switch notif.kind {
    case "mention": return T("mentioned you")
    case "dm": return T("sent you a message")
    case "comment_own": return T("replied to your thread")
    case "comment_followed": return T("commented on a thread you follow")
    case "moved": return T("moved your post to its own thread")
    default: return T("new activity")
    }
}

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
                    ContentUnavailableView(T("You’re all caught up"),
                                           systemImage: "bell.slash",
                                           description: Text(T("New mentions, replies and messages will appear here.")))
                } else {
                    List(store.items) { notif in
                        Button { open(notif) } label: { NotifRow(notif: notif) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(T("Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.items.isEmpty {
                        Button(T("Mark all read")) { Task { await store.markAllSeen() } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Plain green text, not the iOS 26 prominent black-pill glass button.
                    Button { dismiss() } label: {
                        Text(T("Done")).fontWeight(.semibold).foregroundStyle(Color.dcAccent)
                    }
                    .buttonStyle(.plain)
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
                (Text(notif.actor?.name ?? T("Someone")).fontWeight(.semibold)
                 + Text(" \(notifKindLabel(notif))").foregroundColor(.secondary))
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
        .accessibilityLabel(count > 0 ? T("Notifications, {n} unread").replacingOccurrences(of: "{n}", with: "\(count)") : T("Notifications"))
    }
}
