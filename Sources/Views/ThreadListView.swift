import SwiftUI

/// Forum thread list, styled like the dcamp web board: title + New message,
/// filter pills, and rich rows (subject, category, preview, author + machine).
struct ThreadListView: View {
    let board: Board
    @Binding var path: [Dest]

    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ForumFilterStore.self) private var forumFilter
    @State private var rows: [MessageRow] = []
    @State private var total = 0
    @State private var fetched = 0              // server offset for the next page (rows may skip repeats)
    @State private var loadedFor: String?       // filter the rows were loaded with
    @State private var loading = false
    @State private var statusFilter: ProblemStatus = .unsolved
    @State private var composing = false
    @State private var showFilter = false

    private let api = DcampAPI.shared

    enum ProblemStatus: String, CaseIterable { case unsolved, solved, notaproblem, all }

    private func statusLabel(_ s: ProblemStatus) -> String {
        switch s { case .unsolved: return T("Unsolved"); case .solved: return T("Solved"); case .notaproblem: return T("Closed"); case .all: return T("All") }
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
        .sheet(isPresented: $showFilter) {
            FilterSheet(onApply: { Task { await load(reset: true) } })
                .environment(session).environment(forumFilter)
        }
        // .task re-runs every time the list reappears (back from a thread): reloading then
        // cut the rows to the first page and lost the reader's place, so only refresh the
        // rows already shown unless the filter changed meanwhile.
        .task(id: board.id) {
            if rows.isEmpty || loadedFor != filterKey { await load(reset: true) } else { await refreshInPlace() }
        }
        .refreshable { await load(reset: true) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Image(systemName: ForumStyle.icon(board))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(ForumStyle.tint(board), in: RoundedRectangle(cornerRadius: 8))
                Text(T(board.name)).font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.dcInk)
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
                            DCFilterPill(icon: statusIcon(s), title: statusLabel(s), active: statusFilter == s) {
                                statusFilter = s; Task { await load(reset: true) }
                            }
                        }
                    }
                }
            }
            filterControl
        }
    }

    /// A single "Filter" affordance that opens the shared FilterSheet (involvement
    /// + Countries + saved filters). With a selection it becomes a chip showing the
    /// active filter (tap to edit) plus an on/off toggle — matching the web.
    @ViewBuilder private var filterControl: some View {
        HStack(spacing: 8) {
            if forumFilter.selected {
                DCFilterPill(icon: "line.3.horizontal.decrease", title: forumFilter.label, active: forumFilter.on) {
                    showFilter = true
                }
                DCFilterPill(icon: forumFilter.on ? "checkmark.circle" : "circle",
                             title: forumFilter.on ? T("Filter on") : T("Filter off"), active: forumFilter.on) {
                    forumFilter.toggleOn(); Task { await load(reset: true) }
                }
            } else {
                DCFilterPill(icon: "line.3.horizontal.decrease", title: T("Filter"), active: false) {
                    showFilter = true
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

    private var filterKey: String {
        "\(statusFilter.rawValue) \(forumFilter.messageParams.sorted { $0.key < $1.key })"
    }

    private func pageParams(offset: Int) -> [String: String] {
        var params = ["project_id": String(board.id), "offset": String(offset), "limit": "30"]
        params.merge(forumFilter.messageParams) { _, new in new }   // popular / mine / countries
        if isProblems && statusFilter != .all { params["status"] = statusFilter.rawValue }
        return params
    }

    private func load(reset: Bool) async {
        if loading { return }
        loading = true; defer { loading = false }
        let offset = reset ? 0 : fetched
        if let page: MessagesPage = try? await api.call("messages", pageParams(offset: offset)) {
            // Latest-activity order: a thread that got a reply since the last page shifts the
            // rest down, so the next page repeats a row. Skip it (duplicate ForEach ids).
            if reset { rows = page.messages }
            else { let have = Set(rows.map(\.id)); rows.append(contentsOf: page.messages.filter { !have.contains($0.id) }) }
            fetched = offset + page.messages.count
            total = page.total ?? rows.count
            loadedFor = filterKey
        }
    }

    /// Back from a thread: update the newest page's rows (reply counts, latest reply) in
    /// place, without adding or removing rows, so the scroll position stays put.
    private func refreshInPlace() async {
        guard let page: MessagesPage = try? await api.call("messages", pageParams(offset: 0)) else { return }
        let fresh = Dictionary(page.messages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in rows.indices { if let f = fresh[rows[i].id], f != rows[i] { rows[i] = f } }
    }
}

// MARK: - Thread row

struct ThreadRowView: View {
    let row: MessageRow
    @State private var width: CGFloat?

    private let picSize: CGFloat = 52
    private let gap: CGFloat = 12
    /// Below this row width the picture floats top-right and the title wraps
    /// around it; wider rows (iPad, Mac) keep the picture as a leading column.
    private let floatBelow: CGFloat = 560

    var body: some View {
        Group {
            if let w = width, w < floatBelow {
                // Phones: in a leading column the title got only what the picture
                // left over; floated, it wraps around the picture then runs full width.
                FloatRightLayout(picSize: picSize, gap: gap, spacing: 6) {
                    picture
                    ThreadTitle(row: row, narrowWidth: w - picSize - gap, beside: picSize)
                    details
                }
            } else {
                HStack(alignment: .top, spacing: gap) {
                    picture
                    VStack(alignment: .leading, spacing: 6) {
                        ThreadTitle(row: row, narrowWidth: nil, beside: 0)
                        details
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var picture: some View {
        if let url = row.thumbURL {
            AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                placeholder: { Color.dcLine }
                .frame(width: picSize, height: picSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            // No thread graphic → fall back to the author's avatar (as the web
            // does), so every row keeps a 52pt picture slot and the titles all
            // wrap at the same width instead of some going full-bleed.
            Avatar(person: row.author, size: picSize)
        }
    }

    @ViewBuilder private var details: some View {
        // Own line: beside the title, a long label left the title a few letters per line.
        if let cat = row.categoryName, !cat.isEmpty { CategoryPill(name: cat, emoji: row.categoryEmoji) }
        if !row.displayPreview.isEmpty {
            Text(row.displayPreview).font(.system(size: 15)).foregroundStyle(Color.dcInkSoft).lineLimit(1)
        }
        if let rc = row.recentCommentText, !PlainText.strip(rc).isEmpty {
            Label(PlainText.strip(rc), systemImage: "arrowshape.turn.up.left")
                .font(.system(size: 13)).foregroundStyle(Color.dcMuted).lineLimit(1)
        }
        AuthorLine(person: row.author, date: row.createdAt, commentCount: row.commentCount)
    }
}

/// Thread title. With `narrowWidth`, the lines that start beside the floated
/// picture (the top `beside` points) are laid out at that width and the rest
/// at full width — SwiftUI has no text float, so the title is measured and split.
private struct ThreadTitle: View {
    let row: MessageRow
    let narrowWidth: CGFloat?
    let beside: CGFloat

    private static let fontSize: CGFloat = 18

    var body: some View {
        if let narrowWidth {
            let (head, tail) = split(narrowWidth)
            VStack(alignment: .leading, spacing: 0) {
                styled(head, pin: row.isPinned).frame(width: narrowWidth, alignment: .leading)
                if !tail.isEmpty { styled(tail, pin: false) }
            }
        } else {
            styled(row.displaySubject, pin: row.isPinned)
        }
    }

    private func styled(_ s: String, pin: Bool) -> some View {
        (pin ? Text(Image(systemName: "pin.fill")).font(.caption2).foregroundColor(.orange) + Text("  ") : Text(""))
            + Text(s).font(.system(size: Self.fontSize, weight: .bold)).foregroundColor(Color.dcInk)
    }

    /// Splits the subject after the last line that starts beside the picture.
    private func split(_ width: CGFloat) -> (String, String) {
        let subject = row.displaySubject
        // An em space stands in for the pin icon + gap when measuring.
        let prefix = row.isPinned ? "\u{2003}" : ""
        let text = prefix + subject
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: Self.fontSize, weight: .bold)])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var end = 0, lines = 0, total = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            total += 1
            if rect.minY < beside || lines == 0 {
                lines += 1
                end = NSMaxRange(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
            }
        }
        guard lines < total else { return (subject, "") }
        let cut = max(0, end - (prefix as NSString).length)
        let sub = subject as NSString
        return (sub.substring(to: cut).trimmingCharacters(in: .whitespaces),
                sub.substring(from: cut).trimmingCharacters(in: .whitespaces))
    }
}

/// `pic` (the first subview) pinned top-right; the rest stack with `spacing`,
/// narrowed to clear the picture while they start beside it. The second subview
/// (the title) always gets the full width — it handles its own split.
private struct FloatRightLayout: Layout {
    let picSize: CGFloat
    let gap: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        return CGSize(width: w, height: arrange(width: w, subviews: subviews, origin: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = arrange(width: bounds.width, subviews: subviews, origin: bounds.origin)
    }

    private func arrange(width: CGFloat, subviews: Subviews, origin: CGPoint?) -> CGFloat {
        guard let pic = subviews.first else { return 0 }
        let narrow = max(0, width - picSize - gap)
        if let o = origin {
            pic.place(at: CGPoint(x: o.x + width - picSize, y: o.y), proposal: .init(width: picSize, height: picSize))
        }
        var y: CGFloat = 0
        for (i, v) in subviews.dropFirst().enumerated() {
            let w = i > 0 && y < picSize ? narrow : width
            let h = v.sizeThatFits(.init(width: w, height: nil)).height
            if let o = origin { v.place(at: CGPoint(x: o.x, y: o.y + y), proposal: .init(width: w, height: h)) }
            y += h + spacing
        }
        return max(y - spacing, picSize)
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
