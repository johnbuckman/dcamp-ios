import Foundation
import Observation

struct BookmarkTarget: Hashable, Sendable {
    let messageID: Int
    var commentID: Int = 0
    var key: String { "\(messageID):\(commentID)" }
}

/// The existing web `bookmarks_list` item. A post and a comment in the same
/// conversation are separate bookmarks; preserve the server's ordering.
struct BookmarkItem: Codable, Identifiable {
    let messageId: Int
    let commentId: Int
    var createdAt: Int?
    var projectId: Int?
    var projectName: String?
    var subject: String?
    var slug: String?
    var route: String?
    var snippet: String?
    var author: Person?

    var target: BookmarkTarget { BookmarkTarget(messageID: messageId, commentID: commentId) }
    var id: String { target.key }
}

struct BookmarksResponse: Decodable {
    var items: [BookmarkItem]
    var total: Int?
}

/// `message.bookmarks` uses the web's 0/1 message flag and comment-ID array.
struct ThreadBookmarks: Codable {
    var m: Int = 0
    var c: [Int] = []
}

protocol BookmarksAPI: Sendable {
    func bookmarksList(limit: Int?) async throws -> BookmarksResponse
    func bookmarkSet(target: BookmarkTarget, on: Bool) async throws
}

extension DcampAPI: BookmarksAPI {
    func bookmarksList(limit: Int? = nil) async throws -> BookmarksResponse {
        try await call("bookmarks_list", limit.map { ["limit": String($0)] } ?? [:])
    }

    func bookmarkSet(target: BookmarkTarget, on: Bool) async throws {
        _ = try await rawData("bookmark_set", ["id": String(target.messageID),
                                               "c": String(target.commentID), "on": on ? "1" : "0"])
    }
}

@MainActor @Observable
final class BookmarkListState {
    var items: [BookmarkItem] = []
    var isLoading = false
    var hasLoaded = false
    var error: String?
    fileprivate var request = 0
    fileprivate let limit: Int?

    init(limit: Int? = nil) { self.limit = limit }
}

/// Shared across the page, recent list, sidebar and post/comment menus for the
/// current session. Nothing is saved locally: reopening fetches the web's list.
@MainActor @Observable
final class BookmarksStore {
    let recent = BookmarkListState(limit: 15)
    let all = BookmarkListState()
    private(set) var pending: BookmarkTarget?
    private(set) var revision = 0
    private var threads: [Int: ThreadBookmarks] = [:]
    private let api: any BookmarksAPI

    init(api: any BookmarksAPI = DcampAPI.shared) { self.api = api }

    func isBookmarked(_ target: BookmarkTarget) -> Bool {
        if let state = threads[target.messageID] {
            return target.commentID == 0 ? state.m != 0 : state.c.contains(target.commentID)
        }
        return all.items.contains { $0.target == target } || recent.items.contains { $0.target == target }
    }

    func applyThread(_ state: ThreadBookmarks?, messageID: Int, at requestedRevision: Int) {
        // A polling response started before a save/remove must not undo that action.
        guard let state, requestedRevision == revision, pending == nil else { return }
        threads[messageID] = state
    }

    func load(_ list: BookmarkListState) async {
        list.request += 1
        let request = list.request, requestedRevision = revision
        list.isLoading = true
        list.error = nil
        // Keep the first fetch queued while a write is in flight. Its terminal
        // refresh below will fetch authoritative data after the write settles.
        guard pending == nil else { return }
        defer {
            if request == list.request {
                list.isLoading = requestedRevision != revision || pending != nil
            }
        }
        do {
            let result = try await api.bookmarksList(limit: list.limit)
            guard request == list.request, requestedRevision == revision, pending == nil else { return }
            list.items = result.items
            list.hasLoaded = true
            if list.limit == nil {
                // A fresh full list also updates menus for threads already visited.
                for mid in Array(threads.keys) {
                    let items = result.items.filter { $0.messageId == mid }
                    threads[mid] = ThreadBookmarks(m: items.contains { $0.commentId == 0 } ? 1 : 0,
                                                    c: items.compactMap { $0.commentId > 0 ? $0.commentId : nil })
                }
            }
        } catch {
            guard request == list.request, requestedRevision == revision else { return }
            list.error = error.localizedDescription
        }
    }

    func set(_ target: BookmarkTarget, on: Bool) async throws {
        guard pending == nil else { return }
        pending = target
        revision += 1
        do {
            try await api.bookmarkSet(target: target, on: on)
        } catch {
            pending = nil
            revision += 1
            await reloadRequestedLists()
            throw error
        }
        revision += 1
        var state = threads[target.messageID] ?? ThreadBookmarks(
            m: isBookmarked(BookmarkTarget(messageID: target.messageID)) ? 1 : 0,
            c: all.items.filter { $0.messageId == target.messageID && $0.commentId > 0 }.map(\.commentId))
        if target.commentID == 0 { state.m = on ? 1 : 0 }
        else {
            state.c.removeAll { $0 == target.commentID }
            if on { state.c.append(target.commentID) }
        }
        threads[target.messageID] = state
        if !on {
            recent.items.removeAll { $0.target == target }
            all.items.removeAll { $0.target == target }
        }
        pending = nil
        // Re-fetch both open lists, including their server-provided order/previews.
        await reloadRequestedLists()
    }

    private func reloadRequestedLists() async {
        async let recentLoad: Void = reloadIfUsed(recent)
        async let allLoad: Void = reloadIfUsed(all)
        _ = await (recentLoad, allLoad)
    }

    private func reloadIfUsed(_ list: BookmarkListState) async {
        if list.request > 0 { await load(list) }
    }
}
