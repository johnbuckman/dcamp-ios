import SwiftUI

/// Full-text search across threads, comments and chat, plus people.
struct SearchView: View {
    @Binding var path: [Dest]
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var response = SearchResponse()
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @State private var types: Set<String> = ["messages", "comments", "chat"]
    @State private var years = 0
    private let api = DcampAPI.shared
    private let allTypes: [(String, String)] = [("messages", "Threads"), ("comments", "Comments"), ("chat", "Chat"), ("dms", "DMs")]

    var body: some View {
        List {
            Section {
                filterBar
            }
            if !response.people.isEmpty {
                Section("People") {
                    ForEach(response.people) { person in
                        Button { router.personID = person.id } label: {
                            HStack(spacing: 10) {
                                Avatar(person: person, size: 32)
                                Text(person.name).foregroundStyle(Color.dcInk)
                                MachineBadge(person: person)
                            }
                        }
                    }
                }
            }
            if !response.results.isEmpty {
                Section("Threads & comments") {
                    ForEach(response.results, id: \.uid) { hit in
                        Button { open(hit) } label: { SearchHitRow(hit: hit) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dcBg)
        .overlay { emptyState }
        .searchable(text: $query, prompt: "Search dcamp")
        .onChange(of: query) { _, q in schedule(q) }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTypes, id: \.0) { key, label in
                    DCFilterPill(icon: "line.3.horizontal.decrease", title: label, active: types.contains(key)) {
                        if types.contains(key) { types.remove(key) } else { types.insert(key) }
                        schedule(query)
                    }
                }
                Menu {
                    Button("Any year") { years = 0; schedule(query) }
                    ForEach([1, 2, 3, 5].map { $0 }, id: \.self) { y in
                        Button("Past \(y) year\(y == 1 ? "" : "s")") { years = y; schedule(query) }
                    }
                } label: {
                    DCFilterPill(icon: "calendar", title: years == 0 ? "Any year" : "\(years)y", active: years != 0) {}
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    @ViewBuilder private var emptyState: some View {
        if searching {
            ProgressView()
        } else if query.count >= 2 && response.results.isEmpty && response.people.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if query.count < 2 {
            ContentUnavailableView("Search dcamp", systemImage: "magnifyingglass",
                                   description: Text("Find threads, comments, chat and people."))
        }
    }

    private func schedule(_ q: String) {
        task?.cancel()
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { response = SearchResponse(); return }
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            searching = true; defer { searching = false }
            let t = types.isEmpty ? "messages,comments,chat" : types.joined(separator: ",")
            if let r = try? await api.search(q, types: t, years: years) { response = r }
        }
    }

    private func open(_ hit: SearchHit) {
        if let mid = DcampRoute.messageID(from: hit.link) { path.append(.thread(mid)) }
    }
}

struct SearchHitRow: View {
    let hit: SearchHit
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(Color.dcMuted)
                Text(hit.title ?? "Untitled").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dcInk).lineLimit(1)
            }
            if let s = hit.snippet, !s.isEmpty {
                Text(PlainText.strip(s)).font(.system(size: 13)).foregroundStyle(Color.dcInkSoft).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
    private var icon: String {
        switch hit.type {
        case "comment": return "bubble.left"
        case "chat": return "bubble.left.and.bubble.right"
        default: return "text.bubble"
        }
    }
}
