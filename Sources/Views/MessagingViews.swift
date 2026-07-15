import SwiftUI

// Shared helpers ------------------------------------------------------------

/// Wrap plain composer text as the minimal Trix-compatible HTML dcamp stores.
func plainToHTML(_ text: String) -> String {
    let esc = text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    let paras = esc.components(separatedBy: "\n").filter { !$0.isEmpty }
    return paras.map { "<p>\($0)</p>" }.joined()
}

/// One-line send composer used by chat and DMs (green Send, warm styling).
struct SendBar: View {
    var placeholder: String = "Message…"
    @Binding var text: String
    var sending: Bool
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dcLineStrong, lineWidth: 1))
            Button(action: onSend) {
                Text("Send")
            }
            .buttonStyle(DCPrimaryButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? 0.5 : 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.dcBg)
    }
}

/// A flat author-headed message row (chat + DM + comments), matching the web:
/// name + DECENT + machine badge on top, rendered body below.
struct LineRow: View {
    let author: Person?
    let html: String
    let createdAt: Int?
    var translated: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AuthorLine(person: author, date: createdAt)
            TranslatableText(original: html, translated: translated).font(.system(size: 15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

// Chat ----------------------------------------------------------------------

@MainActor
@Observable
final class ChatStore {
    var lines: [ChatLine] = []
    private var lastID = 0
    private let api = DcampAPI.shared
    private let realtime: RealtimeService = PollingRealtime()

    func start() async {
        await reload()
        realtime.start(interval: 6) { [weak self] in await self?.poll() }
    }
    func stop() { realtime.stop() }
    func reload() async {
        if let r = try? await api.chatLines() {
            lines = r.lines; lastID = r.lastId ?? lines.last?.id ?? 0
        }
    }
    private func poll() async {
        guard let r = try? await api.chatLines(since: lastID) else { return }
        let existing = Set(lines.map(\.id))
        let new = r.lines.filter { !existing.contains($0.id) }
        if !new.isEmpty { lines.append(contentsOf: new) }
        lastID = r.lastId ?? lines.last?.id ?? lastID
    }
    func send(html: String) async {
        guard !PlainText.strip(html).isEmpty else { return }
        try? await api.chatPost(bodyHTML: html)
        await reload()
    }
}

struct ChatView: View {
    @Environment(SessionStore.self) private var session
    @State private var store = ChatStore()
    @State private var editingLine: ChatLine?
    private let api = DcampAPI.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SummarizeBar(kind: .chat).padding(.bottom, 4)
                        VStack(spacing: 0) {
                            ForEach(store.lines) { line in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        LineRow(author: line.author, html: line.html, createdAt: line.createdAt, translated: line.bodyTr)
                                        if session.isAdmin {
                                            Menu {
                                                Button { editingLine = line } label: { Label("Edit", systemImage: "pencil") }
                                                Button(role: .destructive) { Task { await api.chatDelete(id: line.id); await store.reload() } } label: { Label("Delete", systemImage: "trash") }
                                            } label: { Image(systemName: "ellipsis").foregroundStyle(Color.dcMuted).padding(4) }
                                        }
                                    }
                                    BoostBar(type: "chat", id: line.id, boosts: line.boosts ?? Boosts()) { await store.reload() }
                                        .padding(.bottom, 8)
                                }
                                .id(line.id)
                                Divider().background(Color.dcLine)
                            }
                        }
                        .dcCard(padding: 8)
                    }
                    .padding(18)
                    .dcColumn()
                }
                .onChange(of: store.lines.count) {
                    if let last = store.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            InlineComposer(placeholder: "Message the room… (rich text, @mention)") { html in
                await store.send(html: html)
            }
        }
        .background(Color.dcBg)
        .navigationTitle("Chat Room")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingLine) { line in
            ComposeView(mode: .editChat(line: line)) { _ in Task { await store.reload() } }
        }
        .task { await store.start() }
        .onDisappear { store.stop() }
    }
}

// Direct messages -----------------------------------------------------------

struct DMListView: View {
    @Binding var path: [Dest]
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var convos: [DMConversation] = []
    @State private var loading = false
    @State private var composing = false
    @State private var pendingConvo: Int?
    @State private var selected: Int?      // iPad two-pane selection
    private let api = DcampAPI.shared

    private var twoPane: Bool { hSize == .regular }

    var body: some View {
        Group {
            if twoPane {
                HStack(spacing: 0) {
                    listColumn.frame(width: 340)
                    Divider()
                    if let c = selected {
                        DMThreadView(convoID: c).id(c)
                    } else {
                        ContentUnavailableView("Select a conversation", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                listColumn
            }
        }
        .background(Color.dcBg)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $composing, onDismiss: {
            if let c = pendingConvo { pendingConvo = nil; open(c) }
        }) {
            NewDMView { convoID in pendingConvo = convoID }
        }
        .task { await load() }
    }

    private var listColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Direct Messages").font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                    Spacer()
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).foregroundStyle(Color.dcAccent)
                }
                if convos.isEmpty && !loading {
                    ContentUnavailableView("No messages yet", systemImage: "envelope",
                                           description: Text("Start a private conversation.")).padding(.top, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(convos) { c in
                            Button { open(c.id) } label: {
                                DMConversationRow(convo: c)
                                    .background(twoPane && selected == c.id ? Color.dcAccent.opacity(0.08) : .clear)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await api.dmArchive(convoID: c.id); await load() }
                                } label: { Label("Archive", systemImage: "archivebox") }
                            }
                            Divider().background(Color.dcLine)
                        }
                    }
                    .dcCard(padding: 4)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .background(Color.dcBg)
        .refreshable { await load() }
    }

    private func open(_ id: Int) {
        if twoPane { selected = id } else { path.append(.dm(id)) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let list = try? await api.dmConversations() { convos = list }
    }
}

struct DMConversationRow: View {
    let convo: DMConversation
    var body: some View {
        HStack(spacing: 12) {
            Avatar(person: convo.lead, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.dcInk).lineLimit(1)
                Text(PlainText.strip(convo.last ?? "")).font(.system(size: 14)).foregroundStyle(Color.dcInkSoft).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(RelativeTime.string(convo.lastAt)).font(.system(size: 12)).foregroundStyle(Color.dcMuted)
                if convo.unreadCount > 0 {
                    Text("\(convo.unreadCount)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.dcAccent, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

@MainActor
@Observable
final class DMThreadStore {
    var thread = DMThread()
    private var convoID = 0
    private let api = DcampAPI.shared
    private let realtime: RealtimeService = PollingRealtime()

    func start(convoID: Int) async {
        self.convoID = convoID
        await reload()
        realtime.start(interval: 6) { [weak self] in await self?.reload() }
    }
    func stop() { realtime.stop() }
    func reload() async { if let t = try? await api.dmThread(convoID: convoID) { thread = t } }
    func send(html: String) async {
        guard !PlainText.strip(html).isEmpty else { return }
        try? await api.dmSend(convoID: convoID, bodyHTML: html)
        await reload()
    }
}

struct DMThreadView: View {
    let convoID: Int
    @State private var store = DMThreadStore()
    @State private var showInvite = false
    private let api = DcampAPI.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.thread.messages) { m in
                            DMBubble(message: m).id(m.id)
                        }
                    }
                    .padding(16)
                    .dcColumn()
                }
                .onChange(of: store.thread.messages.count) {
                    if let last = store.thread.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            InlineComposer(placeholder: "Write a direct message… (rich text, @mention)") { html in
                await store.send(html: html)
            }
        }
        .background(Color.dcBg)
        .navigationTitle(store.thread.members.map(\.name).joined(separator: ", "))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showInvite = true } label: { Label("Add people", systemImage: "person.badge.plus") }
                    if store.thread.members.count > 1 {
                        Menu("Remove") {
                            ForEach(store.thread.members) { p in
                                Button(p.name) { Task { await api.dmRemove(convoID: convoID, personID: p.id); await store.reload() } }
                            }
                        }
                    }
                } label: { Image(systemName: "person.2") }
            }
        }
        .sheet(isPresented: $showInvite) {
            PeopleSearchSheet(title: "Invite") { r in
                await api.dmInvite(convoID: convoID, participantIDs: [r.id], days: 30)
                await store.reload()
                return nil
            }
        }
        .task(id: convoID) { await store.start(convoID: convoID) }
        .onDisappear { store.stop() }
    }
}

/// iMessage-style DM bubble (own = blue/right, others = grey/left), matching the
/// dcamp web DM thread.
struct DMBubble: View {
    let message: DMMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine {
                Spacer(minLength: 44)
                bubble
                Avatar(person: message.sender, size: 28)
            } else {
                Avatar(person: message.sender, size: 28)
                bubble
                Spacer(minLength: 44)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            TranslatableText(original: message.html, translated: message.bodyTr)
                .font(.system(size: 15))
                .foregroundStyle(message.isMine ? Color.white : Color.dcInk)
            Text(RelativeTime.string(message.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(message.isMine ? Color.white.opacity(0.75) : Color.dcMuted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            message.isMine ? Color.dcLink : Color(red: 0.94, green: 0.93, blue: 0.90),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

/// Reusable people search list. `onPick` does the async work (create/invite) and
/// returns an error string on failure; the sheet dismisses on success.
struct PeopleSearchSheet: View {
    var title: String
    var onPick: (Recipient) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Recipient] = []
    @State private var busy = false
    @State private var error: String?
    private let api = DcampAPI.shared

    var body: some View {
        NavigationStack {
            List(results) { r in
                Button {
                    busy = true
                    Task { if let e = await onPick(r) { error = e; busy = false } else { dismiss() } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle").foregroundStyle(Color.dcMuted)
                        Text(r.name).foregroundStyle(Color.dcInk)
                        Spacer()
                        if busy { ProgressView() } else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.dcMuted) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(busy)
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("Find someone", systemImage: "person.2",
                                           description: Text("Search people by name."))
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .onChange(of: query) { _, q in Task { await runSearch(q) } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Something went wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func runSearch(_ q: String) async {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        if let r = try? await api.pingRecipients(query: q) { results = r }
    }
}

struct NewDMView: View {
    var onCreated: (Int) -> Void
    private let api = DcampAPI.shared

    var body: some View {
        PeopleSearchSheet(title: "New message") { r in
            do { onCreated(try await api.dmCreate(participantIDs: [r.id])); return nil }
            catch { return (error as? DcampAPI.APIError)?.message ?? error.localizedDescription }
        }
    }
}
