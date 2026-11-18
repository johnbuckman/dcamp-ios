import XCTest
@testable import dcamp

@MainActor
final class BookmarksTests: XCTestCase {
    private var post: BookmarkTarget { BookmarkTarget(messageID: 100) }
    private var comment: BookmarkTarget { BookmarkTarget(messageID: 100, commentID: 12) }

    func testDecodeWebListAndPerThreadFlags() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BookmarksResponse.self, from: Data(##"{"ok":true,"total":2,"items":[{"message_id":100,"comment_id":0,"project_id":1,"project_name":"General Forum","created_at":1000,"subject":"Coffee","route":"#/message/100","snippet":"Preview","author":{"id":7,"name":"Member"}},{"message_id":100,"comment_id":12,"subject":"Coffee","route":"#/message/100?c=12"}]}"##.utf8))
        XCTAssertEqual(response.items.map(\.id), ["100:0", "100:12"])
        XCTAssertEqual(response.items[1].target, comment)
        XCTAssertEqual(response.items[0].projectName, "General Forum")
        let state = try decoder.decode(ThreadBookmarks.self, from: Data(##"{"m":1,"c":[12,15]}"##.utf8))
        XCTAssertEqual(state.m, 1)
        XCTAssertEqual(state.c, [12,15])
    }

    func testNativeRequestsMatchWebActionsAndParameters() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BookmarkURLProtocol.self]
        let api = DcampAPI(session: URLSession(configuration: config))
        BookmarkURLProtocol.handler = { request in
            let form = URLComponents(string: "https://test.invalid/?" + String(data: request.httpBody!, encoding: .utf8)!)!.queryItems!
            let params = Dictionary(uniqueKeysWithValues: form.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(params["action"], "bookmarks_list")
            XCTAssertEqual(params["limit"], "15")
            return Data(##"{"ok":true,"items":[],"total":0}"##.utf8)
        }
        _ = try await api.bookmarksList(limit: 15)
        for target in [post, comment] {
            for on in [true, false] {
                BookmarkURLProtocol.handler = { request in
                    let form = URLComponents(string: "https://test.invalid/?" + String(data: request.httpBody!, encoding: .utf8)!)!.queryItems!
                    let params = Dictionary(uniqueKeysWithValues: form.map { ($0.name, $0.value ?? "") })
                    XCTAssertEqual(params["action"], "bookmark_set")
                    XCTAssertEqual(params["id"], "100")
                    XCTAssertEqual(params["c"], String(target.commentID))
                    XCTAssertEqual(params["on"], on ? "1" : "0")
                    return Data(##"{"ok":true}"##.utf8)
                }
                try await api.bookmarkSet(target: target, on: on)
            }
        }
    }

    func testRecentLimitAndFullListKeepServerOrder() async {
        let api = BookmarkMock(items: [BookmarkFixture.item(commentID: 12), BookmarkFixture.item()] +
                               (201...220).map { BookmarkFixture.item(messageID: $0) })
        let store = BookmarksStore(api: api)
        await store.load(store.recent)
        await store.load(store.all)
        XCTAssertEqual(store.recent.items.count, 15)
        XCTAssertEqual(store.all.items.count, 22)
        XCTAssertEqual(store.all.items.first?.target, comment)
    }

    func testRemovingCommentKeepsPostAndUpdatesBothLists() async throws {
        let api = BookmarkMock(items: [BookmarkFixture.item(), BookmarkFixture.item(commentID: 12)])
        let store = BookmarksStore(api: api)
        await store.load(store.recent)
        await store.load(store.all)
        store.applyThread(ThreadBookmarks(m: 1, c: [12]), messageID: 100, at: store.revision)
        try await store.set(comment, on: false)
        XCTAssertTrue(store.isBookmarked(post))
        XCTAssertFalse(store.isBookmarked(comment))
        XCTAssertEqual(store.all.items.map(\.target), [post])
        XCTAssertEqual(store.recent.items.map(\.target), [post])
    }

    func testSavingPostDoesNotRemoveItsCommentBookmark() async throws {
        let api = BookmarkMock(items: [BookmarkFixture.item(commentID: 12)])
        let store = BookmarksStore(api: api)
        await store.load(store.all)
        try await store.set(post, on: true)
        XCTAssertTrue(store.isBookmarked(post))
        XCTAssertTrue(store.isBookmarked(comment))
        XCTAssertEqual(store.all.items.first?.target, post)
    }

    func testWriteFailureKeepsConfirmedStateAndItems() async {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        await store.load(store.all)
        await api.failWrites()
        do { try await store.set(post, on: false); XCTFail("Expected the server error") } catch {}
        XCTAssertTrue(store.isBookmarked(post))
        XCTAssertEqual(store.all.items.count, 1)
        XCTAssertNil(store.pending)
    }

    func testFetchFailureIsDifferentFromAnEmptyListAndCanRetry() async {
        let api = BookmarkMock(items: [])
        let store = BookmarksStore(api: api)
        await api.failReads(true)
        await store.load(store.all)
        XCTAssertNotNil(store.all.error)
        XCTAssertFalse(store.all.hasLoaded)
        await api.failReads(false)
        await store.load(store.all)
        XCTAssertNil(store.all.error)
        XCTAssertTrue(store.all.hasLoaded)
        XCTAssertTrue(store.all.items.isEmpty)
    }

    func testStaleThreadPollCannotUndoSave() async throws {
        let store = BookmarksStore(api: BookmarkMock(items: []))
        let before = store.revision
        try await store.set(post, on: true)
        store.applyThread(ThreadBookmarks(), messageID: 100, at: before)
        XCTAssertTrue(store.isBookmarked(post))
    }

    func testRefreshingFullListPicksUpWebChangesInMenus() async {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        store.applyThread(ThreadBookmarks(m: 1), messageID: 100, at: store.revision)
        await store.load(store.all)
        await api.replaceItems([BookmarkFixture.item(commentID: 12)])
        await store.load(store.all)
        XCTAssertFalse(store.isBookmarked(post))
        XCTAssertTrue(store.isBookmarked(comment))
    }

    func testEarlierListRequestCannotRestoreRemovedBookmark() async throws {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        await store.load(store.all)
        await api.suspendNextRead()
        let oldLoad = Task { await store.load(store.all) }
        await api.waitForSuspension()
        try await store.set(post, on: false)
        await api.resumeRead()
        await oldLoad.value
        XCTAssertTrue(store.all.items.isEmpty)
        XCTAssertFalse(store.isBookmarked(post))
    }

    func testListsOpenedDuringSaveLoadAfterWriteCompletes() async throws {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        await api.suspendNextWrite()
        let save = Task { try await store.set(comment, on: true) }
        await api.waitForWriteSuspension()
        await store.load(store.recent)
        await store.load(store.all)
        XCTAssertTrue(store.recent.isLoading)
        XCTAssertTrue(store.all.isLoading)
        await api.resumeWrite()
        try await save.value
        for list in [store.recent, store.all] {
            XCTAssertTrue(list.hasLoaded)
            XCTAssertFalse(list.isLoading)
            XCTAssertNil(list.error)
            XCTAssertEqual(list.items.map(\.target), [comment, post])
        }
    }

    func testListsOpenedDuringFailedSaveLoadExistingBookmarks() async {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        await api.suspendNextWrite()
        await api.failWrites()
        let save = Task {
            do { try await store.set(comment, on: true); return false }
            catch { return true }
        }
        await api.waitForWriteSuspension()
        await store.load(store.recent)
        await store.load(store.all)
        await api.resumeWrite()
        let failed = await save.value
        XCTAssertTrue(failed)
        for list in [store.recent, store.all] {
            XCTAssertTrue(list.hasLoaded)
            XCTAssertFalse(list.isLoading)
            XCTAssertNil(list.error)
            XCTAssertEqual(list.items.map(\.target), [post])
        }
        XCTAssertNil(store.pending)
    }

    func testFailedWriteRetriesAnInvalidatedInitialFetch() async {
        let api = BookmarkMock(items: [BookmarkFixture.item()])
        let store = BookmarksStore(api: api)
        await api.suspendNextRead()
        let firstLoad = Task { await store.load(store.all) }
        await api.waitForSuspension()
        await api.failWrites()
        do { try await store.set(comment, on: true); XCTFail("Expected write failure") } catch {}
        XCTAssertTrue(store.all.hasLoaded)
        XCTAssertEqual(store.all.items.map(\.target), [post])
        await api.resumeRead()
        await firstLoad.value
        XCTAssertFalse(store.all.isLoading)
        XCTAssertEqual(store.all.items.map(\.target), [post])
    }
}

private actor BookmarkMock: BookmarksAPI {
    var items: [BookmarkItem]
    private var failRead = false, failWrite = false, suspend = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var suspendWrite = false
    private var heldWrite: CheckedContinuation<Void, Never>?
    private var writeWaiter: CheckedContinuation<Void, Never>?
    init(items: [BookmarkItem]) { self.items = items }
    func failReads(_ value: Bool) { failRead = value }
    func failWrites() { failWrite = true }
    func replaceItems(_ items: [BookmarkItem]) { self.items = items }
    func suspendNextRead() { suspend = true }
    func waitForSuspension() async {
        if held == nil { await withCheckedContinuation { waiter = $0 } }
    }
    func resumeRead() { held?.resume(); held = nil }
    func suspendNextWrite() { suspendWrite = true }
    func waitForWriteSuspension() async {
        if heldWrite == nil { await withCheckedContinuation { writeWaiter = $0 } }
    }
    func resumeWrite() { heldWrite?.resume(); heldWrite = nil }
    func bookmarksList(limit: Int?) async throws -> BookmarksResponse {
        if failRead { throw DcampAPI.APIError(message: "Unavailable", code: "test") }
        let snapshot = Array(items.prefix(limit ?? items.count))
        if suspend {
            suspend = false
            await withCheckedContinuation {
                held = $0; waiter?.resume(); waiter = nil
            }
        }
        return BookmarksResponse(items: snapshot, total: snapshot.count)
    }
    func bookmarkSet(target: BookmarkTarget, on: Bool) async throws {
        if suspendWrite {
            suspendWrite = false
            await withCheckedContinuation {
                heldWrite = $0; writeWaiter?.resume(); writeWaiter = nil
            }
        }
        if failWrite { throw DcampAPI.APIError(message: "Unavailable", code: "test") }
        items.removeAll { $0.target == target }
        if on { items.insert(BookmarkFixture.item(messageID: target.messageID, commentID: target.commentID), at: 0) }
    }
}

private final class BookmarkURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // URLSession may move POST bodies to a stream before calling URLProtocol.
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            request.httpBody = data
        }
        let data = Self.handler!(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
