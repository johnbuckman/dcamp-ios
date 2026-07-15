import SwiftUI

/// Loads an AI summary for a given target + window. Shared by the inline bar and
/// the pinned sidebar.
enum SummaryLoader {
    static func load(_ kind: SummaryKind, days: Int) async throws -> String {
        let api = DcampAPI.shared
        let r: SummaryResult
        switch kind {
        case .home: r = try await api.homeSummary(days: days)
        case .forum(let id, _): r = try await api.forumSummary(projectID: id, days: days)
        case .thread(let id): r = try await api.threadSummary(messageID: id, days: days)
        case .chat: r = try await api.chatSummary(days: days)
        }
        return r.summary ?? "<p>No activity in this window.</p>"
    }
}

/// The ✨ Summarize bar. Works like the web: pick a window, hit Summarize, and the
/// summary expands inline below the bar (Show/Hide). On iPad, "Show in sidebar"
/// pins it to a persistent side panel.
struct SummarizeBar: View {
    let kind: SummaryKind

    @Environment(SummaryPin.self) private var pin
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var days = 7
    @State private var expanded = false
    @State private var html: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Menu {
                    ForEach([1, 7, 14, 30], id: \.self) { d in
                        Button("past \(d) day\(d == 1 ? "" : "s")") { days = d; if expanded { Task { await reload() } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("past \(days) day\(days == 1 ? "" : "s")").font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.dcInkSoft)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.dcPanel, in: Capsule())
                    .overlay(Capsule().stroke(Color.dcLineStrong, lineWidth: 1))
                }
                Button(expanded ? "Hide" : "Summarize") { toggle() }.buttonStyle(DCPrimaryButtonStyle())
                if expanded && hSize == .regular {
                    Button { pinToSidebar() } label: { Label("Show in sidebar", systemImage: "sidebar.left") }
                        .font(.system(size: 13))
                }
                Spacer()
            }

            if expanded {
                Group {
                    if loading {
                        HStack(spacing: 8) { ProgressView(); Text("Summarizing…").font(.footnote).foregroundStyle(Color.dcMuted) }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if let html {
                        TrixContentView(html: html).font(.system(size: 15))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: DC.radius))
                .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(Color.dcLine, lineWidth: 1))
            }
        }
    }

    private func toggle() {
        if expanded { expanded = false } else { expanded = true; Task { await reload() } }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        html = (try? await SummaryLoader.load(kind, days: days))
    }
    private func pinToSidebar() {
        pin.kind = kind; pin.days = days; pin.title = kind.label
        expanded = false
    }
}

/// Persistent iPad side panel showing the pinned summary.
struct SummarySidebarView: View {
    @Environment(SummaryPin.self) private var pin
    @State private var html: String?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Text(pin.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.dcInk).lineLimit(1)
                Spacer()
                Button { pin.clear() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dcMuted) }
            }
            .padding(12)
            Divider().background(Color.dcLine)
            ScrollView {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if let html {
                    TrixContentView(html: html).font(.system(size: 14)).padding(14)
                }
            }
        }
        .background(Color.dcBg)
        .task(id: pinKey) { await load() }
    }

    private var pinKey: String { "\(String(describing: pin.kind))-\(pin.days)" }
    private func load() async {
        guard let kind = pin.kind else { return }
        loading = true; defer { loading = false }
        html = (try? await SummaryLoader.load(kind, days: pin.days))
    }
}
