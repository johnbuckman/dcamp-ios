import SwiftUI

/// Forum thread list, styled like the dcamp web board: title + New message,
/// filter pills, and rich rows (subject, category, preview, author + machine).
struct ThreadListView: View {
    let board: Board
    @Binding var path: [Dest]

    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var rows: [MessageRow] = []
    @State private var total = 0
    @State private var loading = false
    @State private var filter: Filter = .all
    @State private var statusFilter: ProblemStatus = .unsolved
    @State private var composing = false

    private let api = DcampAPI.shared

    enum Filter: String { case all, popular, posted, commented, mentioned }
    enum ProblemStatus: String, CaseIterable { case unsolved, solved, notaproblem, all
        var label: String { switch self { case .unsolved: return "Unsolved"; case .solved: return "Solved"; case .notaproblem: return "Closed"; case .all: return "All" } }
    }

    private var isProblems: Bool { board.name == "Problems" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                SummarizeBar(kind: .forum(board.id, board.name))
                filterBar
                threadRows
            }
            .padding(18)
            .dcColumn()
        }
        .background(Color.dcBg)
        .scrollContentBackground(.hidden)
        // No centered nav-bar title — the board name already shows in the content
        // header (icon + name), so a nav title would duplicate it.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $composing) {
            ComposeView(mode: .newThread(board: board)) { newID in
                Task { await load(reset: true) }
                path.append(.thread(newID))
            }
        }
        .task(id: board.id) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Image(systemName: ForumStyle.icon(board))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(ForumStyle.tint(board), in: RoundedRectangle(cornerRadius: 8))
                Text(board.name).font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.dcInk)
            }
            Spacer()
            if session.canPost {
                Button { composing = true } label: { Label(T("New message"), systemImage: "plus") }
                    .buttonStyle(DCPrimaryButtonStyle())
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isProblems {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ProblemStatus.allCases, id: \.self) { s in
                            DCFilterPill(icon: statusIcon(s), title: s.label, active: statusFilter == s) {
                                statusFilter = s; Task { await load(reset: true) }
                            }
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    DCFilterPill(icon: "flame", title: "Popular", active: filter == .popular) { toggle(.popular) }
                    DCFilterPill(icon: "square.and.pencil", title: "I posted", active: filter == .posted) { toggle(.posted) }
                    DCFilterPill(icon: "bubble.left", title: "I commented", active: filter == .commented) { toggle(.commented) }
                    DCFilterPill(icon: "at", title: "I'm mentioned", active: filter == .mentioned) { toggle(.mentioned) }
                }
            }
        }
    }

    private func statusIcon(_ s: ProblemStatus) -> String {
        switch s { case .unsolved: return "circle.dashed"; case .solved: return "checkmark.circle"; case .notaproblem: return "xmark.circle"; case .all: return "circle.grid.2x2" }
    }

    @ViewBuilder private var threadRows: some View {
        if loading && rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else if rows.isEmpty {
            ContentUnavailableView(T("No threads yet"), systemImage: "tray").padding(.top, 30)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    Button { router.threadSiblings = rows.map(\.id); path.append(.thread(row.id)) } label: { ThreadRowView(row: row) }
                        .buttonStyle(.plain)
                        // Load the next page as the last row scrolls in. onAppear on the
                        // last row re-fires as the list grows (a single trailing sentinel
                        // with .task only ever fired once → the endless-spinner bug).
                        .onAppear { if row.id == rows.last?.id { Task { await load(reset: false) } } }
                    Divider().background(Color.dcLine)
                }
                if loading && rows.count < total {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
            .dcCard(padding: 4)
        }
    }

    private func toggle(_ f: Filter) {
        filter = (filter == f) ? .all : f
        Task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if loading { return }
        loading = true; defer { loading = false }
        let offset = reset ? 0 : rows.count
        var params = ["project_id": String(board.id), "offset": String(offset), "limit": "30"]
        switch filter {
        case .popular: params["popular"] = "1"
        case .posted: params["mine"] = "posted"
        case .commented: params["mine"] = "commented"
        case .mentioned: params["mine"] = "mentioned"
        case .all: break
        }
        if isProblems && statusFilter != .all { params["status"] = statusFilter.rawValue }
        if let page: MessagesPage = try? await api.call("messages", params) {
            if reset { rows = page.messages } else { rows.append(contentsOf: page.messages) }
            total = page.total ?? rows.count
        }
    }
}

// MARK: - Thread row

struct ThreadRowView: View {
    let row: MessageRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = row.thumbURL {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.dcLine }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if row.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                    Text(row.displaySubject).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.dcInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cat = row.categoryName, !cat.isEmpty { CategoryPill(name: cat, emoji: row.categoryEmoji) }
                }
                if !row.displayPreview.isEmpty {
                    Text(row.displayPreview).font(.system(size: 15)).foregroundStyle(Color.dcInkSoft).lineLimit(1)
                }
                if let rc = row.recentCommentText, !PlainText.strip(rc).isEmpty {
                    Label(PlainText.strip(rc), systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 13)).foregroundStyle(Color.dcMuted).lineLimit(1)
                }
                HStack(spacing: 8) {
                    AuthorLine(person: row.author, date: row.createdAt)
                    if let n = row.commentCount, n > 0 {
                        Text("·").foregroundStyle(Color.dcMuted)
                        Label("\(n)", systemImage: "bubble.right").font(.system(size: 13)).foregroundStyle(Color.dcMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct CategoryPill: View {
    let name: String
    var emoji: String?
    var body: some View {
        HStack(spacing: 3) {
            if let e = emoji, !e.isEmpty { Image(systemName: sfName(e)).font(.system(size: 10)) }
            Text(name)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.dcAccentInk)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Color.dcAccent.opacity(0.12), in: Capsule())
    }
    // dcamp stores FontAwesome-ish names; map a few common ones to SF Symbols.
    private func sfName(_ n: String) -> String {
        switch n {
        case "handshake-angle", "handshake": return "hands.sparkles"
        case "circle-question", "question": return "questionmark.circle"
        default: return "tag"
        }
    }
}
