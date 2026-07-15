import SwiftUI
import UIKit

/// Thread view: summarize bar, a message card (avatar + subject + author/machine
/// line + body + reactions + ⋯ menu), and author-headed comments with reactions
/// and their own ⋯ menus.
struct ThreadDetailView: View {
    let messageID: Int

    @Environment(SessionStore.self) private var session
    @State private var currentID: Int
    @State private var message: MessageDetail?
    @State private var comments: [Comment] = []
    @State private var loading = false
    @State private var editingMessage: MessageDetail?
    @State private var editingComment: Comment?
    @State private var composerModel = ComposerModel()
    @State private var scrollTick = 0

    private let api = DcampAPI.shared

    init(messageID: Int) {
        self.messageID = messageID
        _currentID = State(initialValue: messageID)
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
                                commentRow(c)
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
        .sheet(item: $editingMessage) { m in
            ComposeView(mode: .editThread(message: m)) { _ in Task { await load() } }
        }
        .sheet(item: $editingComment) { c in
            ComposeView(mode: .editComment(comment: c)) { _ in Task { await load() } }
        }
        .onChange(of: scrollTick) { withAnimation { proxy.scrollTo("composer", anchor: .bottom) } }
        .task(id: currentID) {
            await load()
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
                Avatar(person: m.author, size: 46)
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
            Button { copyLink(messageID: m.id) } label: { Label("Copy link", systemImage: "link") }
            if session.canPost {
                Button { quote(m.html) } label: { Label("Quote & reply", systemImage: "quote.opening") }
            }
            if canModify(m.author?.id) {
                Button { editingMessage = m } label: { Label("Edit", systemImage: "pencil") }
                Menu("Mark as") {
                    Button("Unsolved") { setStatus("active", for: m.id) }
                    Button("Solved") { setStatus("solved", for: m.id) }
                    Button("Closed") { setStatus("closed", for: m.id) }
                }
                if session.isAdmin {
                    Button { pin(m) } label: { Label(m.pinned == 1 ? "Unpin" : "Pin", systemImage: "pin") }
                }
                Button(role: .destructive) { deleteMessage(m) } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(Color.dcMuted).padding(6)
        }
    }

    // MARK: comment row

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(person: c.author, size: 34)
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
            Button { copyLink(messageID: currentID, commentID: c.id) } label: { Label("Copy link", systemImage: "link") }
            if session.canPost {
                Button { quote(c.html) } label: { Label("Quote & reply", systemImage: "quote.opening") }
            }
            if canModify(c.author?.id) {
                Button { editingComment = c } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { deleteComment(c) } label: { Label("Delete", systemImage: "trash") }
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
                Text("Add a comment").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.dcInk)
                InlineComposer(placeholder: "Write a comment… (rich text, @mention)", model: composerModel) { html in
                    _ = try? await api.createComment(messageID: currentID, bodyHTML: html)
                    await load()
                }
                .background(Color.dcPanel)
                .clipShape(RoundedRectangle(cornerRadius: DC.radius))
                .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(Color.dcLine, lineWidth: 1))
            }
            .padding(.top, 6)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "lock").foregroundStyle(Color.dcMuted)
                Text("You have read-only access — posting is for current Decent machine owners.")
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
    private func deleteMessage(_ m: MessageDetail) { Task { await api.messageStatus(id: m.id, status: "deleted"); await load() } }
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
