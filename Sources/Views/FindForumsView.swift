import SwiftUI

/// Discover & join regional / roaster forums (the web's "Find" page). Gated on
/// show_regions / show_roasters from bootstrap.
struct FindForumsView: View {
    @Environment(SessionStore.self) private var session
    @State private var regions: [Board] = []
    @State private var roasters: [Board] = []
    @State private var loading = true

    private let api = DcampAPI.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(T("Find forums")).font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.dcInk)
                if session.showRegions { section("Regional forums", regions, kind: "region") }
                if session.showRoasters { section("Roaster forums", roasters, kind: "roaster") }
                if !loading && regions.isEmpty && roasters.isEmpty {
                    ContentUnavailableView(T("Nothing to discover"), systemImage: "map",
                                           description: Text(T("No regional or roaster forums are available yet.")))
                        .padding(.top, 30)
                }
            }
            .padding(18).dcColumn()
        }
        .background(Color.dcBg)
        .scrollContentBackground(.hidden)
        .navigationTitle(T("Find forums")).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func section(_ title: String, _ boards: [Board], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DCSectionLabel(text: title)
            VStack(spacing: 0) {
                ForEach(boards) { b in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.dcInk)
                            if let d = b.description, !d.isEmpty {
                                Text(d).font(.footnote).foregroundStyle(Color.dcInkSoft).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(b.isJoined ? T("Leave") : T("Join")) { toggle(b, kind: kind) }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(b.isJoined ? Color.dcMuted : Color.dcAccentInk)
                    }
                    .padding(12)
                    Divider().background(Color.dcLine)
                }
            }
            .dcCard(padding: 4)
        }
    }

    private func toggle(_ b: Board, kind: String) {
        Task {
            if b.isJoined { await api.projectLeave(id: b.id) } else { await api.projectJoin(id: b.id) }
            await load()
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if session.showRegions { regions = await api.projectsDiscover(kind: "region") }
        if session.showRoasters { roasters = await api.projectsDiscover(kind: "roaster") }
    }
}
