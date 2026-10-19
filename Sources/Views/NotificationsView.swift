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

/// Notification inbox = the recent-activity feed (same list + read state as the
/// web's top-bar bell): unread first (dotted), then an "Earlier" separator and the
/// read history. Tapping a row marks it read and hands its route to `onOpen`.
struct NotificationsView: View {
    let store: NotificationsStore
    var onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var firstReadID: String? {
        guard store.feed.contains(where: { !$0.isRead }) else { return nil }
        return store.feed.first(where: { $0.isRead })?.id
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.feed.isEmpty && store.loadingFeed {
                    ProgressView()
                } else if store.feed.isEmpty {
                    ContentUnavailableView(T("You’re all caught up"),
                                           systemImage: "bell.slash",
                                           description: Text(T("New mentions, replies and messages will appear here.")))
                } else {
                    List {
                        ForEach(store.feed) { item in
                            if item.id == firstReadID {
                                Text(T("Earlier")).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    .textCase(.uppercase).listRowSeparator(.hidden)
                            }
                            Button { open(item) } label: { ActivityRow(item: item) }
                                .buttonStyle(.plain)
                        }
                        if store.canLoadMore {
                            Button {
                                Task { await store.loadFeed(limit: store.feedLimit + 80) }
                            } label: {
                                HStack { Spacer(); Label(T("Load more"), systemImage: "chevron.down"); Spacer() }
                            }
                            .disabled(store.loadingFeed)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.loadFeed() }
                }
            }
            .navigationTitle(T("Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.feed.contains(where: { !$0.isRead }) {
                        Button(T("Mark all read")) { Task { await store.markAllRead() } }
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
            .task { await store.loadFeed(limit: 80) }
        }
    }

    private func open(_ item: ActivityItem) {
        Task { await store.markRead(item) }
        guard let route = item.route, !route.isEmpty else { return }
        onOpen(route)
        dismiss()
    }
}

/// One feed row: avatar + kind badge, thread title (with "@mentioned you in:" / "Re:"
/// prefix and "+N more"), preview, and "when · who" — mirroring the web's act-row.
struct ActivityRow: View {
    let item: ActivityItem

    private var title: String {
        let base = (item.subject?.isEmpty == false ? item.subject! : (item.actor?.name ?? ""))
        switch item.kind {
        case "comment_own", "comment_followed": return T("Re:") + " " + base
        default: return base
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Avatar(person: item.actor, size: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Color(hex: item.badgeHex) ?? Color.accentColor, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 5, y: -5)
            }
            VStack(alignment: .leading, spacing: 3) {
                if item.kind == "mention" {
                    Text(T("@mentioned you in:")).font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "#7c3aed") ?? .purple)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !item.isRead { Circle().fill(Color.red).frame(width: 7, height: 7) }
                    Text(PlainText.strip(title)).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if item.moreCount > 0 {
                        Text("+\(item.moreCount) " + T("more"))
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                if let p = item.preview, !p.isEmpty {
                    Text(PlainText.strip(p)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(RelativeTime.string(item.createdAt) + ((item.actor?.name).map { " · " + $0 } ?? ""))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(item.isRead ? 0.75 : 1)
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
        return collapse(Inline.decodeEntities(s))
    }

    /// Runs of whitespace → one space, trimmed (what a browser shows for a title).
    static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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
