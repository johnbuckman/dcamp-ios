import SwiftUI

/// Web-parity page: saved posts/comments, blue titles, author/forum/save time,
/// a separate remove ×, and the same private-list explanation and empty state.
struct BookmarksView: View {
    @Environment(BookmarksStore.self) private var store
    @Environment(SummaryPin.self) private var pin
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    var onOpen: (BookmarkItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { title; Spacer(); sidebarButton }
                    VStack(alignment: .leading, spacing: 10) { title; sidebarButton }
                }
                Text(T("Posts and comments you've saved, newest first. Only you can see them."))
                    .font(.subheadline).foregroundStyle(Color.dcMuted)
                BookmarkListContent(list: store.all, onOpen: onOpen)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(bookmarkPanel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        colorScheme == .dark ? Color.dcLine : Color(red: 217 / 255, green: 226 / 255, blue: 240 / 255), lineWidth: 1))
            }
            .padding(18).dcColumn()
        }
        .background(Color.dcBg)
        .navigationTitle(T("Bookmarks"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load(store.all) }
        .refreshable { await store.load(store.all) }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await store.load(store.all) } }
        }
    }

    private var title: some View {
        Label(T("Bookmarks"), systemImage: "bookmark.fill")
            .font(.title.bold()).foregroundStyle(Color.dcInk)
    }

    @ViewBuilder private var sidebarButton: some View {
        if hSize == .regular {
            Button {
                pin.clear(); pin.bookmarks = true; pin.title = T("Bookmarks")
            } label: { Label(T("Show in sidebar"), systemImage: "pin.fill") }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pin-bookmarks")
        }
    }

    // The web uses its pale-blue summary panel for the full bookmark list.
    private var bookmarkPanel: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.141, green: 0.125, blue: 0.102, alpha: 1)
            : UIColor(red: 0.965, green: 0.973, blue: 0.984, alpha: 1) })
    }
}

/// The top-bar menu's latest 15 entries and footer, presented natively on iOS.
struct RecentBookmarksView: View {
    @Environment(BookmarksStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onOpen: (BookmarkItem) -> Void
    var onSeeAll: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView { BookmarkListContent(list: store.recent, onOpen: { item in onOpen(item); dismiss() }) }
                    .refreshable { await store.load(store.recent) }
                Divider()
                Button {
                    onSeeAll(); dismiss()
                } label: {
                    Label(T("See all bookmarks"), systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(16)
                }
                .accessibilityIdentifier("see-all-bookmarks")
            }
            .background(Color.dcPanel)
            .navigationTitle(T("Bookmarks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(T("Done")) { dismiss() } } }
            .task { await store.load(store.recent) }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BookmarkSidebarView: View {
    @Environment(BookmarksStore.self) private var store
    @Environment(SummaryPin.self) private var pin
    @Environment(\.scenePhase) private var phase
    var onOpen: (BookmarkItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(T("Bookmarks"), systemImage: "bookmark.fill").font(.headline)
                Spacer()
                Button { pin.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel(T("Hide sidebar"))
            }
            .foregroundStyle(Color.dcMuted).padding(12)
            Divider()
            ScrollView { BookmarkListContent(list: store.all, onOpen: onOpen) }
                .refreshable { await store.load(store.all) }
        }
        .background(Color.dcPanel)
        .task { await store.load(store.all) }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await store.load(store.all) } }
        }
    }
}

private struct BookmarkListContent: View {
    let list: BookmarkListState
    var onOpen: (BookmarkItem) -> Void
    @Environment(BookmarksStore.self) private var store
    @State private var mutationError: String?

    var body: some View {
        VStack(spacing: 0) {
            if list.isLoading && !list.hasLoaded {
                ProgressView().frame(maxWidth: .infinity).padding(36)
            } else if list.items.isEmpty && list.error == nil {
                ContentUnavailableView {
                    Label(T("No bookmarks yet"), systemImage: "bookmark")
                } description: {
                    Text(T("Use “Bookmark” in the ⋯ menu of any post or comment to save it here."))
                }
                .accessibilityIdentifier("bookmarks-empty")
            } else {
                ForEach(list.items) { item in
                    if item.id != list.items.first?.id { Divider().padding(.horizontal, 8) }
                    HStack(alignment: .center, spacing: 0) {
                        Button { onOpen(item) } label: { BookmarkRow(item: item) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bookmark-open-\(item.id)")
                        Button {
                            Task {
                                do { try await store.set(item.target, on: false) }
                                catch { mutationError = error.localizedDescription }
                            }
                        } label: {
                            Image(systemName: "xmark").font(.subheadline)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.dcMuted)
                        .disabled(store.pending != nil)
                        .accessibilityLabel(T("Remove bookmark"))
                        .accessibilityIdentifier("bookmark-remove-\(item.id)")
                    }
                }
            }
            if let error = list.error {
                VStack(spacing: 8) {
                    Text(T("Couldn't load your bookmarks")).font(.headline)
                    Text(error).font(.footnote).foregroundStyle(Color.dcMuted)
                    Button(T("Try again")) { Task { await store.load(list) } }
                }
                .padding(20).frame(maxWidth: .infinity)
                .accessibilityIdentifier("bookmarks-error")
            }
        }
        .alert(T("Couldn’t update bookmark"), isPresented: Binding(
            get: { mutationError != nil }, set: { if !$0 { mutationError = nil } }
        )) { Button(T("OK")) { mutationError = nil } } message: { Text(mutationError ?? "") }
    }
}

private struct BookmarkRow: View {
    let item: BookmarkItem

    private var title: String {
        let subject = item.subject.flatMap { $0.isEmpty ? nil : PlainText.collapse($0) } ?? T("Untitled")
        return item.commentId > 0 ? T("Comment on:") + " " + subject : subject
    }
    private var metadata: String {
        var parts = [item.author?.name, item.projectName].compactMap { $0 }.filter { !$0.isEmpty }
        if let date = item.createdAt {
            let saved = Date(timeIntervalSince1970: TimeInterval(date))
            let when = Date().timeIntervalSince(saved) < 86_400
                ? RelativeTime.string(date) : saved.formatted(date: .numeric, time: .omitted)
            parts.append(T("saved {d}").replacingOccurrences(of: "{d}", with: when))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(person: item.author, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.dcLink)
                    .fixedSize(horizontal: false, vertical: true)
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet).font(.footnote).foregroundStyle(Color.dcInkSoft).lineLimit(2)
                }
                Text(metadata).font(.caption).foregroundStyle(Color.dcMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
