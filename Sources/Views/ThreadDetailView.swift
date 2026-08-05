import SwiftUI
import UIKit

/// Thread view: summarize bar, a message card (avatar + subject + author/machine
/// line + body + reactions + ⋯ menu), and author-headed comments with reactions
/// and their own ⋯ menus.
struct ThreadDetailView: View {
    let messageID: Int
    let commentAnchor: Int?

    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: Int
    @State private var message: MessageDetail?
    @State private var comments: [Comment] = []
    @State private var lastVisit: Int?
    @State private var loading = false
    @State private var editingMessage: MessageDetail?
    @State private var editingComment: Comment?
    @State private var composerModel = ComposerModel()
    @State private var scrollTick = 0
    @State private var prevComposerHeight: CGFloat = 9999   // start high so the initial load never counts as growth
    @State private var pendingDeleteMessage: MessageDetail?
    @State private var pendingDeleteComment: Comment?
    @State private var offtopicCommentID: Int?
    @State private var showOfftopic = false
    @State private var composeError: String?

    private let api = DcampAPI.shared

    init(messageID: Int, commentAnchor: Int? = nil) {
        self.messageID = messageID
        self.commentAnchor = commentAnchor
        _currentID = State(initialValue: messageID)
    }

    // Prev/next thread navigation across the board's ordered thread list.
    private var siblingIndex: Int? { router.threadSiblings.firstIndex(of: currentID) }
    private var prevSibling: Int? { guard let i = siblingIndex, i > 0 else { return nil }; return router.threadSiblings[i - 1] }
    private var nextSibling: Int? { guard let i = siblingIndex, i < router.threadSiblings.count - 1 else { return nil }; return router.threadSiblings[i + 1] }
    private func goto(_ id: Int) { message = nil; comments = []; currentID = id }

    /// The first comment posted after the viewer's previous visit (for the marker).
    private var firstUnreadCommentID: Int? {
        guard let lv = lastVisit, lv > 0 else { return nil }
        return comments.first(where: { ($0.createdAt ?? 0) > lv })?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SummarizeBar(kind: .thread(currentID))
                if let m = message {
                    messageCard(m)
                    if !comments.isEmpty {
                        Text("^[\(comments.count) comment](inflect: true)")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.dcInk).padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(comments) { c in
                                if c.id == firstUnreadCommentID { SinceLastVisitDivider() }
                                commentRow(c).id("c-\(c.id)")
                                Divider().background(Color.dcLine)
                            }
                        }
                        .dcCard(padding: 4)
                    }
                    composerSection.id("composer")
                }
            }
            .padding(18).dcColumn()
        }
        .background(Color.dcBg)
        .scrollContentBackground(.hidden)
        .overlay { if loading && message == nil { ProgressView() } }
        .navigationTitle(message?.displaySubject ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .alert(T("Couldn’t post"), isPresented: Binding(get: { composeError != nil }, set: { if !$0 { composeError = nil } })) {
            Button(T("OK")) { composeError = nil }
        } message: { Text(composeError ?? "") }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if siblingIndex != nil {
                    // Wider tap targets (John: the prev/next buttons were too small).
                    Button { if let p = prevSibling { goto(p) } } label: {
                        Image(systemName: "chevron.up").frame(width: 44, height: 30).contentShape(Rectangle())
                    }.disabled(prevSibling == nil)
                    Button { if let n = nextSibling { goto(n) } } label: {
                        Image(systemName: "chevron.down").frame(width: 44, height: 30).contentShape(Rectangle())
                    }.disabled(nextSibling == nil)
                }
            }
        }
        .sheet(item: $editingMessage) { m in
            ComposeView(mode: .editThread(message: m)) { _ in Task { await load() } }
        }
        .sheet(item: $editingComment) { c in
            ComposeView(mode: .editComment(comment: c)) { _ in Task { await load() } }
        }
        .onChange(of: scrollTick) { withAnimation { proxy.scrollTo("composer", anchor: .bottom) } }
        // As the bottom composer grows while typing, keep it (and the cursor) on screen
        // instead of letting it run off the bottom of the page. Only reacts to GROWTH,
        // so opening the thread never yanks the view down to the composer.
        .onChange(of: composerModel.contentHeight) { _, h in
            if h > prevComposerHeight + 1 { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("composer", anchor: .bottom) } }
            prevComposerHeight = h
        }
        .confirmationDialog(T("Delete this post?"), isPresented: Binding(get: { pendingDeleteMessage != nil }, set: { if !$0 { pendingDeleteMessage = nil } }), titleVisibility: .visible) {
            Button(T("Delete"), role: .destructive) { if let m = pendingDeleteMessage { pendingDeleteMessage = nil; deleteMessage(m) } }
            Button(T("Cancel"), role: .cancel) { pendingDeleteMessage = nil }
        } message: { Text(T("This removes the whole thread. This can’t be undone.")) }
        .confirmationDialog(T("Delete this comment?"), isPresented: Binding(get: { pendingDeleteComment != nil }, set: { if !$0 { pendingDeleteComment = nil } }), titleVisibility: .visible) {
            Button(T("Delete"), role: .destructive) { if let c = pendingDeleteComment { pendingDeleteComment = nil; deleteComment(c) } }
            Button(T("Cancel"), role: .cancel) { pendingDeleteComment = nil }
        } message: { Text(T("This can’t be undone.")) }
        .confirmationDialog(T("Move to its own thread?"), isPresented: $showOfftopic, titleVisibility: .visible) {
            Button(T("Move it")) { if let cid = offtopicCommentID { moveOfftopic(cid) } }
            Button(T("Keep it here"), role: .cancel) {}
        } message: { Text(T("This comment looks like it’s about something else. Move it to its own thread?")) }
        .task(id: currentID) {
            await load()
            // Deep-link to a specific comment, else jump to the first unread.
            try? await Task.sleep(nanoseconds: 350_000_000)
            if let cid = commentAnchor { withAnimation { proxy.scrollTo("c-\(cid)", anchor: .center) } }
            else if let uid = firstUnreadCommentID { withAnimation { proxy.scrollTo("c-\(uid)", anchor: .top) } }
            // Live updates: new comments + streaming @derek/@deepseek replies.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                await pollUpdate()
            }
        }
        }
    }

    // MARK: message card

    private func messageCard(_ m: MessageDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(person: m.author, size: 46, tappable: true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if m.pinned == 1 { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                        Text(m.displaySubject).font(.system(size: 24, weight: .heavy)).foregroundStyle(Color.dcInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AuthorLine(person: m.author, date: m.createdAt)
                }
                Spacer(minLength: 0)
                messageMenu(m)
            }
            TranslatableText(original: m.html, translated: m.bodyTr, onRoute: route).font(.system(size: 16))
            BoostBar(type: "message", id: m.id, boosts: m.boosts ?? Boosts()) { await load() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dcCard()
    }

    private func messageMenu(_ m: MessageDetail) -> some View {
        Menu {
            Button { copyLink(messageID: m.id) } label: { Label(T("Copy link"), systemImage: "link") }
            if session.canPost {
                Button { quote(m.html) } label: { Label(T("Quote & reply"), systemImage: "quote.opening") }
            }
            if canModify(m.author?.id) {
                Button { editingMessage = m } label: { Label(T("Edit"), systemImage: "pencil") }
                // Problems-status control only applies to threads on the Problems board
                // (matches the web: isProblemsProject && author-or-admin). The server
                // tokens are unsolved / solved / notaproblem — NOT active/closed.
                if isProblemsThread(m) {
                    Menu(T("Mark as")) {
                        Button(T("Unsolved")) { setStatus("unsolved", for: m.id) }
                        Button(T("Solved")) { setStatus("solved", for: m.id) }
                        Button(T("Closed")) { setStatus("notaproblem", for: m.id) }
                    }
                }
                if session.isAdmin {
                    Button { pin(m) } label: { Label(m.pinned == 1 ? T("Unpin") : T("Pin"), systemImage: "pin") }
                }
                Button(role: .destructive) { pendingDeleteMessage = m } label: { Label(T("Delete"), systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(Color.dcMuted).padding(6)
        }
    }

    // MARK: comment row

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(person: c.author, size: 34, tappable: true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    AuthorLine(person: c.author, date: c.createdAt)
                    Spacer(minLength: 0)
                    commentMenu(c)
                }
                TranslatableText(original: c.html, translated: c.bodyTr, onRoute: route)
                BoostBar(type: "comment", id: c.id, boosts: c.boosts ?? Boosts()) { await load() }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentMenu(_ c: Comment) -> some View {
        Menu {
            Button { copyLink(messageID: currentID, commentID: c.id) } label: { Label(T("Copy link"), systemImage: "link") }
            if session.canPost {
                Button { quote(c.html) } label: { Label(T("Quote & reply"), systemImage: "quote.opening") }
            }
            if canModify(c.author?.id) {
                Button { editingComment = c } label: { Label(T("Edit"), systemImage: "pencil") }
                Button(role: .destructive) { pendingDeleteComment = c } label: { Label(T("Delete"), systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(Color.dcMuted).padding(4)
        }
    }

    /// Inline comment composer at the end of the thread (or a read-only notice),
    /// matching the web where the Trix composer sits at the bottom of the thread.
    @ViewBuilder private var composerSection: some View {
        if session.canPost {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("Add a comment")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dcInk)
                InlineComposer(placeholder: "Write a comment… (rich text, @mention)", model: composerModel, draftKey: "thread:\(currentID)") { html in
                    do {
                        let r = try await api.createComment(messageID: currentID, bodyHTML: html)
                        await load()
                        if let cid = r.id { await checkOfftopic(commentID: cid) }
                        return true
                    } catch {
                        composeError = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
                        return false
                    }
                }
                .background(Color.dcPanel)
                .clipShape(RoundedRectangle(cornerRadius: DC.radius))
                .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(Color.dcLine, lineWidth: 1))
            }
            .padding(.top, 6)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "lock").foregroundStyle(Color.dcMuted)
                Text(T("You have read-only access — posting is for current Decent machine owners."))
                    .font(.footnote).foregroundStyle(Color.dcMuted)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .dcCard()
        }
    }

    // MARK: actions

    private func canModify(_ authorID: Int?) -> Bool {
        guard let authorID else { return false }
        return session.me?.id == authorID || session.isAdmin
    }

    /// True only for threads on the "Problems" board — where message_set_status
    /// (unsolved/solved/notaproblem) is meaningful. Mirrors the web's isProblemsProject.
    private func isProblemsThread(_ m: MessageDetail) -> Bool {
        guard let pid = m.projectId else { return false }
        return session.boards.first(where: { $0.id == pid })?.name == "Problems"
    }

    private func copyLink(messageID: Int, commentID: Int? = nil) {
        var s = "https://decentespresso.com/support/dcamp/#/message/\(messageID)"
        if let commentID { s += "?c=\(commentID)" }
        UIPasteboard.general.string = s
    }
    /// Insert a blockquote of the given content into the reply composer + scroll to it.
    private func quote(_ html: String) {
        let text = PlainText.strip(html)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        composerModel.insertQuote("<p>\(text)</p>")
        scrollTick += 1
    }
    private func setStatus(_ status: String, for id: Int) { Task { await api.messageSetStatus(id: id, status: status); await load() } }
    private func pin(_ m: MessageDetail) { Task { await api.messagePin(id: m.id, pinned: m.pinned != 1); await load() } }
    /// After a comment posts, ask the server whether it reads as off-topic; if so
    /// offer to split it into its own thread (matches the web's always-on auto-triage).
    private func checkOfftopic(commentID: Int) async {
        let s = await api.offtopicSuggest(commentID: commentID)
        if s.suggested { offtopicCommentID = commentID; showOfftopic = true }
    }
    private func moveOfftopic(_ cid: Int) {
        Task {
            let r = await api.offtopicMove(commentID: cid)
            if let newID = r.id { message = nil; currentID = newID }   // navigate to the new thread in place
            else { await load() }
        }
    }
    private func deleteMessage(_ m: MessageDetail) { Task { await api.messageStatus(id: m.id, status: "deleted"); dismiss() } }
    private func deleteComment(_ c: Comment) { Task { await api.commentDelete(id: c.id); await load() } }

    private func route(_ token: String) {
        let path = token.hasPrefix("/") ? String(token.dropFirst()) : token
        let parts = path.split(separator: "/")
        if parts.count >= 2, parts[0] == "message", let id = Int(parts[1].prefix(while: { $0.isNumber })) {
            message = nil; currentID = id
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let resp: MessageResponse = try? await api.call("message", ["id": String(currentID)]) {
            message = resp.message
            comments = resp.comments ?? []
            lastVisit = resp.lastVisit
        }
    }

    /// Poll for new/streaming comments without flashing the whole view. Only
    /// reassigns when something actually changed (count or a streaming body).
    private func pollUpdate() async {
        guard let resp: MessageResponse = try? await api.call("message", ["id": String(currentID)]) else { return }
        let fresh = resp.comments ?? []
        let changed = fresh.count != comments.count ||
            zip(fresh, comments).contains { $0.body != $1.body || $0.streaming != $1.streaming }
        if changed { comments = fresh }
        if resp.message.boosts?.list.count != message?.boosts?.list.count { message = resp.message }
    }
}

/// "New since your last visit" divider inserted before the first unread comment.
struct SinceLastVisitDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.dcAccent.opacity(0.35)).frame(height: 1)
            Text(T("New since your last visit"))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.dcAccentInk).fixedSize()
            Rectangle().fill(Color.dcAccent.opacity(0.35)).frame(height: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
