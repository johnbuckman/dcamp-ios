import SwiftUI

/// Full-text search across threads, comments, chat and DMs, plus people —
/// with facets (type, forum, experts-only), sort, match-quality, term
/// highlighting, row metadata, and an inline "Ask Derek" answer panel.
struct SearchView: View {
    @Binding var path: [Dest]
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var response = SearchResponse()
    @State private var searching = false
    @State private var task: Task<Void, Never>?

    @State private var types: Set<String> = ["messages", "comments", "chat", "pings"]
    @State private var years = 0
    @State private var sortNewest = false
    @State private var goodOnly = false
    @State private var selectedForum: Int? = nil
    @State private var expertsOnly = true

    // Ask-Derek
    @State private var derekAnswer: String? = nil
    @State private var derekLoading = false
    @State private var derekTask: Task<Void, Never>?
    @State private var showHelp = false

    private let api = DcampAPI.shared
    // NB: the server's DM search facet key is "pings" (not "dms").
    private let allTypes: [(String, String)] = [("messages", "Threads"), ("comments", "Comments"), ("chat", "Chat"), ("pings", "DMs")]

    // MARK: derived

    private var visibleResults: [SearchHit] {
        var r = response.results
        if let f = selectedForum { r = r.filter { $0.forumId == f } }
        if goodOnly, let top = r.compactMap({ $0.score }).max(), top > 0 {
            r = r.filter { ($0.score ?? 0) >= top * 0.5 }
        }
        if sortNewest { r.sort { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) } }
        else { r.sort { ($0.score ?? 0) > ($1.score ?? 0) } }
        return r
    }
    private var visiblePeople: [Person] {
        guard expertsOnly, let ex = response.experts, !ex.isEmpty else { return response.people }
        let set = Set(ex)
        let filtered = response.people.filter { set.contains($0.id) }
        return filtered.isEmpty ? response.people : filtered   // auto-fallback to All
    }

    var body: some View {
        List {
            if query.count >= 2 {
                Section { askDerekPanel }
            }
            Section { filterBar }
            if !visiblePeople.isEmpty {
                Section("People (\(visiblePeople.count))") {
                    ForEach(visiblePeople) { person in
                        Button { router.personID = person.id } label: {
                            HStack(spacing: 10) {
                                Avatar(person: person, size: 32)
                                Text(person.name).foregroundStyle(Color.dcInk)
                                MachineBadge(person: person)
                                Spacer()
                                if isExpert(person.id) {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.dcAccent)
                                }
                            }
                        }
                    }
                }
            }
            if !visibleResults.isEmpty {
                Section("Results (\(visibleResults.count))") {
                    ForEach(visibleResults, id: \.uid) { hit in
                        Button { open(hit) } label: { SearchHitRow(hit: hit, terms: queryTerms) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dcBg)
        .overlay { emptyState }
        .searchable(text: $query, prompt: Text(T("Search dcamp")))
        .onChange(of: query) { _, q in schedule(q); derekAnswer = nil; derekTask?.cancel(); derekLoading = false }
        .navigationTitle(T("Search"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "info.circle") }
            }
        }
        .sheet(isPresented: $showHelp) { SearchHelpSheet() }
    }

    // MARK: Ask-Derek

    @ViewBuilder private var askDerekPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = derekAnswer {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Color.dcAccent)
                    Text(T("Derek says")).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.dcInk)
                }
                TrixContentView(html: a, onRoute: routeToken).font(.system(size: 15))
            } else {
                Button { askDerek() } label: {
                    HStack(spacing: 8) {
                        if derekLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "sparkles") }
                        Text(derekLoading ? "Derek is thinking…" : "Ask Derek about “\(query)”")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.dcAccentInk)
                }
                .disabled(derekLoading)
            }
        }
        .padding(.vertical, 2)
    }

    private func askDerek() {
        derekTask?.cancel()
        derekAnswer = nil; derekLoading = true
        let q = query
        derekTask = Task {
            let start = await api.derekSearchStart(q)
            guard let token = start.token, !token.isEmpty else { derekLoading = false; return }
            for _ in 0..<40 {                       // ~28s max
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                let poll = await api.derekSearchPoll(token: token)
                if poll.isDone {
                    derekAnswer = (poll.answer?.isEmpty == false) ? poll.answer : "<p>No answer found.</p>"
                    derekLoading = false
                    return
                }
            }
            derekLoading = false
        }
    }

    // MARK: filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allTypes, id: \.0) { key, label in
                        DCFilterPill(icon: "line.3.horizontal.decrease", title: label, active: types.contains(key)) {
                            if types.contains(key) { types.remove(key) } else { types.insert(key) }
                            schedule(query)
                        }
                    }
                    Menu {
                        Picker(T("Sort"), selection: $sortNewest) {
                            Text(T("Relevance")).tag(false); Text(T("Newest")).tag(true)
                        }
                    } label: { DCFilterPill(icon: "arrow.up.arrow.down", title: sortNewest ? "Newest" : "Relevance", active: false) {}.allowsHitTesting(false) }
                    DCFilterPill(icon: "checkmark.seal", title: "Best matches", active: goodOnly) { goodOnly.toggle() }
                }
            }
            if let forums = response.forums, forums.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DCFilterPill(icon: "square.grid.2x2", title: "All forums", active: selectedForum == nil) { selectedForum = nil }
                        ForEach(forums) { f in
                            DCFilterPill(icon: "bubble.left", title: f.name, active: selectedForum == f.id) {
                                selectedForum = (selectedForum == f.id) ? nil : f.id
                            }
                        }
                    }
                }
            }
            if !response.people.isEmpty, let ex = response.experts, !ex.isEmpty {
                Toggle(isOn: $expertsOnly) { Text(T("Experts only")).font(.system(size: 13, weight: .semibold)) }
                    .toggleStyle(.button).tint(.dcAccent).font(.caption)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    @ViewBuilder private var emptyState: some View {
        if searching {
            ProgressView()
        } else if query.count >= 2 && visibleResults.isEmpty && visiblePeople.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if query.count < 2 {
            ContentUnavailableView(T("Search dcamp"), systemImage: "magnifyingglass",
                                   description: Text(T("Find threads, comments, chat, DMs and people.")))
        }
    }

    // MARK: search + routing

    private var queryTerms: [String] {
        query.lowercased().split(whereSeparator: { $0 == " " }).map(String.init).filter { $0.count >= 2 }
    }
    private func isExpert(_ id: Int) -> Bool { (response.experts ?? []).contains(id) }

    private func schedule(_ q: String) {
        task?.cancel()
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { response = SearchResponse(); return }
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            searching = true; defer { searching = false }
            let t = types.isEmpty ? "messages,comments,chat,pings" : types.joined(separator: ",")
            if let r = try? await api.search(q, types: t, years: years) { response = r; selectedForum = nil }
        }
    }

    private func routeToken(_ token: String) {
        if let id = DcampRoute.messageID(from: token) { path.append(.thread(id)) }
        else if let id = DcampRoute.personID(from: token) { router.personID = id }
    }

    private func open(_ hit: SearchHit) {
        switch hit.type {
        case "chat": path.append(.chat)
        case "pings", "dm":
            if let id = DcampRoute.dmID(from: hit.link) ?? hit.id.map({ $0 }) { path.append(.dm(id)) }
        default:   // message + comment → parent thread
            if let mid = DcampRoute.messageID(from: hit.link) ?? (hit.type == "message" ? hit.id : nil) {
                path.append(.thread(mid))
            }
        }
    }
}

// MARK: - Row

struct SearchHitRow: View {
    let hit: SearchHit
    var terms: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TypePill(type: hit.type)
                Text(highlighted(hit.title ?? "Untitled")).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dcInk).lineLimit(1)
                if hit.isUntranslated {
                    Text(T("not translated")).font(.system(size: 10)).foregroundStyle(Color.dcMuted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.dcLineStrong, lineWidth: 1))
                }
            }
            if let s = hit.snippet, !s.isEmpty {
                Text(highlighted(PlainText.strip(s))).font(.system(size: 13)).foregroundStyle(Color.dcInkSoft).lineLimit(2)
            }
            metaLine
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var metaLine: some View {
        let bits: [String] = [hit.author?.name, hit.forum, hit.createdAt.map { RelativeTime.string($0) }].compactMap { $0 }.filter { !$0.isEmpty }
        if !bits.isEmpty {
            Text(bits.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Color.dcMuted).lineLimit(1)
        }
    }

    /// Bold + accent the query terms inside `text`.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !terms.isEmpty else { return attr }
        let lower = text.lowercased()
        for term in terms {
            var start = lower.startIndex
            while let r = lower.range(of: term, range: start..<lower.endIndex) {
                if let ar = Range(r, in: attr) {
                    attr[ar].foregroundColor = .dcAccentInk
                    attr[ar].inlinePresentationIntent = .stronglyEmphasized
                }
                start = r.upperBound
                if start >= lower.endIndex { break }
            }
        }
        return attr
    }
}

struct TypePill: View {
    let type: String?
    var body: some View {
        Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }
    private var label: String {
        switch type { case "comment": return "COMMENT"; case "chat": return "CHAT"; case "pings", "dm": return "DM"; default: return "THREAD" }
    }
    private var tint: Color {
        switch type { case "comment": return .dcLink; case "chat": return .dcAccent; case "pings", "dm": return Color(red: 0.55, green: 0.36, blue: 0.86); default: return .dcInkSoft }
    }
}

struct SearchHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(T("Tips")) {
                    Label(T("Type two or more letters to search."), systemImage: "textformat")
                    Label(T("Filter by Threads, Comments, Chat or DMs."), systemImage: "line.3.horizontal.decrease")
                    Label(T("Sort by relevance or newest; “Best matches” hides weak hits."), systemImage: "arrow.up.arrow.down")
                    Label(T("“Experts only” narrows people to recognised experts."), systemImage: "star.fill")
                    Label(T("Ask Derek for an AI answer drawn from the whole forum."), systemImage: "sparkles")
                }
            }
            .navigationTitle(T("Search help")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(T("Done")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
