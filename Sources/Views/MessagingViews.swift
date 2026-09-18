import SwiftUI
import UIKit

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
                Text(T("Send"))
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
        HStack(alignment: .top, spacing: 10) {
            Avatar(person: author, size: 36, tappable: true)   // web shows a per-line avatar; native was missing it
            VStack(alignment: .leading, spacing: 5) {
                AuthorLine(person: author, date: createdAt)
                TranslatableText(original: html, translated: translated).font(.system(size: 15))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        realtime.start(interval: 3) { [weak self] in await self?.poll() }
    }
    func stop() { realtime.stop() }
    func reload() async {
        if let r = try? await api.chatLines() {
            lines = r.lines; lastID = r.lastId ?? lines.last?.id ?? 0
        }
    }
    private func poll() async {
        // A streaming @derek/@deepseek line keeps growing under the SAME id. The old
        // dedup-by-id append never updated it, so the partial line was frozen. Re-fetch
        // from just before the lowest streaming id and MERGE by id (update + append).
        let streamingMin = lines.filter { ($0.streaming ?? 0) != 0 }.map(\.id).min()
        let since = streamingMin.map { $0 - 1 } ?? lastID
        guard let r = try? await api.chatLines(since: since) else { return }
        var byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for line in r.lines { byId[line.id] = line }
        lines = byId.values.sorted { $0.id < $1.id }
        lastID = max(lastID, r.lastId ?? lines.last?.id ?? lastID)
    }
    var sendError: String?
    func send(html: String) async -> Bool {
        guard !PlainText.strip(html).isEmpty else { return false }
        do { try await api.chatPost(bodyHTML: html); await reload(); return true }
        catch { sendError = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription; return false }
    }
}

struct ChatView: View {
    @Environment(SessionStore.self) private var session
    @State private var store = ChatStore()
    @State private var editingLine: ChatLine?
    @State private var didInitialScroll = false
    // Owned as @State so it survives the 3s poll re-renders — a fresh ComposerModel
    // each render would have a nil webView, so Send would read empty and no-op.
    @State private var composerModel = ComposerModel()
    private let api = DcampAPI.shared

    private func copyChatLink(_ id: Int) {
        UIPasteboard.general.string = "https://decentespresso.com/support/dcamp/#/chat?m=\(id)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SummarizeBar(kind: .chat).padding(.bottom, 4)
                        VStack(spacing: 0) {
                            ForEach(store.lines) { line in
                                // Chat lines have NO reactions on the web (boosts are messages/comments only).
                                HStack(alignment: .top) {
                                    LineRow(author: line.author, html: line.html, createdAt: line.createdAt, translated: line.bodyTr)
                                    if session.isAdmin {
                                        Menu {
                                            Button { editingLine = line } label: { Label(T("Edit"), systemImage: "pencil") }
                                            Button(role: .destructive) { Task { await api.chatDelete(id: line.id); await store.reload() } } label: { Label(T("Delete"), systemImage: "trash") }
                                        } label: { Image(systemName: "ellipsis").foregroundStyle(Color.dcMuted).padding(4) }
                                    }
                                }
                                .padding(.bottom, 4)
                                .id(line.id)
                                .contextMenu {
                                    Button { copyChatLink(line.id) } label: { Label(T("Link to this"), systemImage: "link") }
                                }
                                Divider().background(Color.dcLine)
                            }
                        }
                        .dcCard(padding: 8)
                    }
                    .padding(18)
                    .dcColumn()
                }
                // Open directly at the most recent line (no scroll from the top);
                // only animate to the bottom for NEW lines after the first fill.
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.lines.count) {
                    guard let last = store.lines.last else { return }
                    if didInitialScroll {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    } else {
                        didInitialScroll = true
                    }
                }
            }
            if session.canPost {
                InlineComposer(placeholder: T("Message the room… (rich text, @mention)"), model: composerModel, draftKey: "chat:main") { html in
                    await store.send(html: html)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "lock").foregroundStyle(Color.dcMuted)
                    Text(T("You have read-only access — chat is for current Decent machine owners."))
                        .font(.footnote).foregroundStyle(Color.dcMuted)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.dcBg)
            }
        }
        .background(Color.dcBg)
        .navigationTitle(T("Chat Room"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(T("Couldn’t send"), isPresented: Binding(get: { store.sendError != nil }, set: { if !$0 { store.sendError = nil } })) {
            Button(T("OK")) { store.sendError = nil }
        } message: { Text(store.sendError ?? "") }
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
    @Environment(SessionStore.self) private var session
    @State private var convos: [DMConversation] = []
    @State private var loading = false
    @State private var composing = false
    @State private var pendingConvo: Int?
    @State private var selected: Int?      // iPad two-pane selection
    @State private var query = ""          // name filter (participant name)
    @State private var offset = 0
    @State private var hasMore = true
    @State private var searchTask: Task<Void, Never>?
    private let api = DcampAPI.shared
    private let pageSize = 30

    private var twoPane: Bool { hSize == .regular }

    /// Client-side name filter — instant, and works even before the server's `q`
    /// param is deployed. Matches participants OTHER than me (else my own name
    /// matches every conversation). The server `q` still runs too, so a deployed
    /// server can search the full history beyond what's been scrolled in.
    private var displayConvos: [DMConversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return convos }
        let myID = session.me?.id
        return convos.filter { c in
            c.members.contains { $0.id != myID && $0.name.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        Group {
            if twoPane {
                HStack(spacing: 0) {
                    listColumn.frame(width: 340)
                    Divider()
                    if let c = selected {
                        DMThreadView(convoID: c).id(c)
                    } else {
                        ContentUnavailableView(T("Select a conversation"), systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                listColumn
            }
        }
        .background(Color.dcBg)
        .navigationTitle(T("Messages"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $composing, onDismiss: {
            if let c = pendingConvo { pendingConvo = nil; open(c) }
        }) {
            NewDMView { convoID in pendingConvo = convoID }
        }
        .task { if convos.isEmpty { await reload() } }
    }

    private var listColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(T("Direct Messages")).font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                    Spacer()
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).foregroundStyle(Color.dcAccent)
                }
                filterField
                if displayConvos.isEmpty && !loading {
                    ContentUnavailableView(
                        query.isEmpty ? T("No messages yet") : T("No matches"),
                        systemImage: query.isEmpty ? "envelope" : "magnifyingglass",
                        description: Text(query.isEmpty ? T("Start a private conversation.")
                                                        : T("No conversations with a participant matching your filter.")))
                        .padding(.top, 30)
                } else {
                    // LazyVStack (not VStack) so each row's onAppear fires when it
                    // actually scrolls into view — a plain VStack renders every row up
                    // front, so the last-row trigger fired during the initial load
                    // (guarded) and never again, stalling the list at page 1.
                    LazyVStack(spacing: 0) {
                        ForEach(displayConvos) { c in
                            Button { open(c.id) } label: {
                                DMConversationRow(convo: c)
                                    .background(twoPane && selected == c.id ? Color.dcAccent.opacity(0.08) : .clear)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await api.dmArchive(convoID: c.id); await reload() }
                                } label: { Label(T("Archive"), systemImage: "archivebox") }
                            }
                            // Fill the list in as the last row scrolls into view.
                            .onAppear { if c.id == displayConvos.last?.id { Task { await loadMore() } } }
                            Divider().background(Color.dcLine)
                        }
                        if loading && !convos.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                    .dcCard(padding: 4)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .background(Color.dcBg)
        .refreshable { await reload() }
    }

    /// Filter box: type a name to show only conversations that person is in.
    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.dcMuted).font(.system(size: 14))
            TextField(T("Filter by name"), text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dcMuted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dcLineStrong, lineWidth: 1))
        .onChange(of: query) { _, _ in
            // Debounce so we re-query the server ~300ms after typing stops.
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await reload()
            }
        }
    }

    private func open(_ id: Int) {
        if twoPane { selected = id } else { path.append(.dm(id)) }
    }

    /// First page (initial load, pull-to-refresh, or filter change).
    private func reload() async {
        loading = true; defer { loading = false }
        let r = try? await api.dmConversations(offset: 0, limit: pageSize, q: query.trimmingCharacters(in: .whitespaces))
        convos = r?.conversations ?? []
        offset = convos.count
        hasMore = r?.hasMore ?? false
    }

    /// Append the next page as the last row scrolls in.
    private func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true; defer { loading = false }
        guard let r = try? await api.dmConversations(offset: offset, limit: pageSize, q: query.trimmingCharacters(in: .whitespaces)) else { return }
        convos.append(contentsOf: r.conversations)
        offset += r.conversations.count
        hasMore = r.hasMore
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
    func reload() async {
        if let t = try? await api.dmThread(convoID: convoID) { thread = t }
    }
    var sendError: String?
    func send(html: String) async -> Bool {
        guard !PlainText.strip(html).isEmpty else { return false }
        do { try await api.dmSend(convoID: convoID, bodyHTML: html); await reload(); return true }
        catch { sendError = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription; return false }
    }
}

struct DMThreadView: View {
    let convoID: Int
    @State private var store = DMThreadStore()
    @State private var showInvite = false
    @State private var didInitialScroll = false
    // Owned as @State so it survives the 6s poll re-renders (see ChatView) — else a
    // fresh ComposerModel per render has a nil webView and Send reads empty → no-op.
    @State private var composerModel = ComposerModel()
    private let api = DcampAPI.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Plain VStack (not lazy): LazyVStack + defaultScrollAnchor(.bottom)
                    // loops forever placing subviews (100% CPU update storm) once the
                    // thread overflows the viewport — ChatView's VStack+anchor works.
                    VStack(spacing: 10) {
                        ForEach(store.thread.messages) { m in
                            DMBubble(message: m, showSender: store.thread.members.count > 2).id(m.id)
                        }
                    }
                    .padding(16)
                    .dcColumn()
                }
                // Open directly at the most recent message (no visible scroll from
                // the top); only animate to the bottom for NEW messages after that.
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.thread.messages.count) {
                    guard let last = store.thread.messages.last else { return }
                    if didInitialScroll {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    } else {
                        didInitialScroll = true      // first fill: already at the bottom via the anchor
                    }
                }
            }
            InlineComposer(placeholder: T("Write a direct message… (rich text, @mention)"), model: composerModel, draftKey: "dm:\(convoID)") { html in
                await store.send(html: html)
            }
        }
        .background(Color.dcBg)
        .navigationTitle(store.thread.members.map(\.name).joined(separator: ", "))
        .navigationBarTitleDisplayMode(.inline)
        .alert(T("Couldn’t send"), isPresented: Binding(get: { store.sendError != nil }, set: { if !$0 { store.sendError = nil } })) {
            Button(T("OK")) { store.sendError = nil }
        } message: { Text(store.sendError ?? "") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showInvite = true } label: { Label(T("Add people"), systemImage: "person.badge.plus") }
                    if store.thread.members.count > 1 {
                        Menu(T("Remove")) {
                            ForEach(store.thread.members) { p in
                                Button(p.name) { Task { await api.dmRemove(convoID: convoID, personID: p.id); await store.reload() } }
                            }
                        }
                    }
                } label: { Image(systemName: "person.2") }
            }
        }
        .sheet(isPresented: $showInvite) {
            PeopleSearchSheet(title: T("Invite")) { r in
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
    var showSender: Bool = false          // group conversations (>2 people)

    // Bigger avatars where there's room (iPad / Mac Catalyst = .pad idiom); keep the
    // compact size on iPhone, where screen width is limited.
    private var avatarSize: CGFloat { UIDevice.current.userInterfaceIdiom == .phone ? 28 : 56 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine {
                Spacer(minLength: 44)
                bubble
                Avatar(person: message.sender, size: avatarSize, tappable: true)
            } else {
                Avatar(person: message.sender, size: avatarSize, tappable: true)
                bubble
                Spacer(minLength: 44)
            }
        }
    }

    private var senderTint: Color { Color(hex: message.sender?.avatarColor) ?? Color.dcAccent }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showSender, !message.isMine, let name = message.sender?.name, !name.isEmpty {
                Text(name).font(.system(size: 11, weight: .bold)).foregroundStyle(senderTint)
            }
            TranslatableText(original: message.html, translated: message.bodyTr, linkColor: message.isMine ? .white : .dcLink)
                .font(.system(size: 15))
                .foregroundStyle(message.isMine ? Color.white : Color.dcInk)
            Text(RelativeTime.string(message.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(message.isMine ? Color.white.opacity(0.75) : Color.dcMuted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            message.isMine ? Color.dcLink : (showSender ? senderTint.opacity(0.14) : Color.dcBubbleOther),
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
                        Avatar(person: r.person, size: 30)
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
                    ContentUnavailableView(T("Find someone"), systemImage: "person.2",
                                           description: Text(T("Search people by name.")))
                }
            }
            .searchable(text: $query, prompt: Text(T("Search people")))
            .onChange(of: query) { _, q in Task { await runSearch(q) } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T("Cancel")) { dismiss() } } }
            .alert(T("Something went wrong"), isPresented: .constant(error != nil)) {
                Button(T("OK")) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func runSearch(_ q: String) async {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        if let r = try? await api.pingRecipients(query: q) { results = r }
    }
}

/// New DM — multi-select people (chips) then start a 1:1 or group conversation.
struct NewDMView: View {
    var onCreated: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Recipient] = []
    @State private var selected: [Recipient] = []
    @State private var busy = false
    @State private var error: String?
    private let api = DcampAPI.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !selected.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selected) { r in
                                HStack(spacing: 4) {
                                    Text(r.name).font(.system(size: 13, weight: .semibold))
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                                }
                                .foregroundStyle(Color.dcAccentInk)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.dcAccent.opacity(0.12), in: Capsule())
                                .onTapGesture { selected.removeAll { $0.id == r.id } }
                            }
                        }.padding(10)
                    }
                    Divider()
                }
                List(results) { r in
                    Button { toggle(r) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected(r) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected(r) ? Color.dcAccent : Color.dcMuted)
                            Avatar(person: r.person, size: 30)
                            Text(r.name).foregroundStyle(Color.dcInk)
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView(T("Find people"), systemImage: "person.2",
                                               description: Text(T("Search by name; pick one or more.")))
                    }
                }
            }
            .searchable(text: $query, prompt: Text(T("Search people")))
            .onChange(of: query) { _, q in Task { await run(q) } }
            .navigationTitle(selected.count > 1 ? T("New group message") : T("New message"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Start")) { start() }.disabled(selected.isEmpty || busy).fontWeight(.semibold)
                }
            }
            .alert(T("Something went wrong"), isPresented: .constant(error != nil)) {
                Button(T("OK")) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func isSelected(_ r: Recipient) -> Bool { selected.contains { $0.id == r.id } }
    private func toggle(_ r: Recipient) {
        if isSelected(r) { selected.removeAll { $0.id == r.id } } else { selected.append(r) }
    }
    private func run(_ q: String) async {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        if let r = try? await api.pingRecipients(query: q) { results = r }
    }
    private func start() {
        busy = true
        Task {
            do { onCreated(try await api.dmCreate(participantIDs: selected.map(\.id))); dismiss() }
            catch { self.error = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription; busy = false }
        }
    }
}
