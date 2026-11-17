import SwiftUI

/// "Send link to…": shown when a URL is shared into dcamp from Safari, Brave or
/// any other app's share sheet (ShareExtension → `dcamp-share://dm?…` →
/// `Router.pendingShare`). Lists the user's DM conversations most recent first
/// (the server's `dm_conversations` order), with a name filter, and "New message"
/// for someone not in the list. Picking one does NOT send: it puts the link into
/// that DM's composer draft and `onPick` hands MainView the conversation id to
/// open once the sheet is gone, so the user can add context and press Send.
struct ShareToDMView: View {
    let link: SharedLink
    var onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var convos: [DMConversation] = []
    @State private var loading = false
    @State private var offset = 0
    @State private var hasMore = true
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var error: String?
    @State private var composingNew = false
    @State private var newConvo: Int?
    private let api = DcampAPI.shared
    private let pageSize = 30

    private var displayConvos: [DMConversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return convos }
        let myID = session.me?.id
        return convos.filter { c in
            c.members.contains { $0.id != myID && $0.name.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    linkCard
                    switch session.phase {
                    case .loggedIn:
                        if let error {
                            Text(error).font(.system(size: 14)).foregroundStyle(.red)
                        }
                        filterField
                        Button { composingNew = true } label: {
                            Label(T("New message"), systemImage: "square.and.pencil")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.dcAccent)
                        convoList
                    case .loggedOut:
                        loginPrompt
                    case .launching:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
                .padding(18)
            }
            .scrollContentBackground(.hidden)
            .background(Color.dcBg)
            .navigationTitle(T("Send link to…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Cancel")) { dismiss() } }
            }
        }
        .sheet(isPresented: $composingNew, onDismiss: {
            if let c = newConvo { newConvo = nil; pick(c) }
        }) {
            NewDMView { convoID in newConvo = convoID }
        }
        // Load the DM list once logged in (now, or right after signing in here).
        .task(id: session.phase == .loggedIn) {
            if session.phase == .loggedIn && convos.isEmpty { await reload() }
        }
    }

    /// Logged out: nothing but a way to sign in. The DM list appears in place
    /// once the browser sign-in completes.
    private var loginPrompt: some View {
        VStack(spacing: 12) {
            Text(T("Log in to send this link"))
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.dcInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let msg = session.errorMessage {
                Text(msg).font(.system(size: 13)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await session.loginWithBrowser() }
            } label: {
                HStack(spacing: 8) {
                    if session.loggingIn { ProgressView().tint(.white) }
                    else { Image(systemName: "safari") }
                    Text(session.loggingIn ? T("Signing in…") : T("Log in"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DCPrimaryButtonStyle())
            .disabled(session.loggingIn)
        }
        .padding(.top, 6)
    }

    // MARK: - Pieces

    private var linkCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "link").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dcAccent)
                .frame(width: 36, height: 36)
                .background(Color.dcAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title.isEmpty ? link.url : link.title)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.dcInk).lineLimit(2)
                Text(URL(string: link.url)?.host ?? link.url)
                    .font(.system(size: 13)).foregroundStyle(Color.dcMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .dcCard(padding: 12)
    }

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
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await reload()
            }
        }
    }

    @ViewBuilder private var convoList: some View {
        if displayConvos.isEmpty {
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            } else {
                ContentUnavailableView(
                    query.isEmpty ? T("No messages yet") : T("No matches"),
                    systemImage: query.isEmpty ? "envelope" : "magnifyingglass")
                    .padding(.top, 20)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(displayConvos) { c in
                    Button { pick(c.id) } label: { DMConversationRow(convo: c) }
                    .buttonStyle(.plain)
                    .onAppear { if c.id == displayConvos.last?.id { Task { await loadMore() } } }
                    Divider().background(Color.dcLine)
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .dcCard(padding: 4)
        }
    }

    // MARK: - Data

    private func reload() async {
        offset = 0; hasMore = true; loading = true
        defer { loading = false }
        do {
            let page = try await api.dmConversations(offset: 0, limit: pageSize, q: query.trimmingCharacters(in: .whitespaces))
            convos = page.conversations
            offset = page.conversations.count
            hasMore = page.hasMore
            error = nil
        } catch let e as DcampAPI.APIError where e.isAuthLost {
            await session.authLost()        // → the page shows only "Log in"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        guard let page = try? await api.dmConversations(offset: offset, limit: pageSize, q: query.trimmingCharacters(in: .whitespaces)) else { return }
        let seen = Set(convos.map(\.id))
        convos += page.conversations.filter { !seen.contains($0.id) }
        offset += page.conversations.count
        hasMore = page.hasMore
    }

    /// Drop the link into that DM's draft (after anything already drafted there)
    /// and open it. Nothing is sent until the user presses Send.
    private func pick(_ convoID: Int) {
        ComposerModel.appendToDraft(key: "dm:\(convoID)", html: Self.draftHTML(link: link))
        onPick(convoID)
        dismiss()
    }

    /// Trix-style HTML for the draft: an empty first line (where the cursor waits
    /// for the user's own words), then the link with the page title as its text.
    static func draftHTML(link: SharedLink) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let text = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<div><br><a href=\"\(esc(link.url))\">\(esc(text.isEmpty ? link.url : text))</a></div>"
    }
}
