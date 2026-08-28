import SwiftUI

/// Loads an AI summary for a given target + window. Shared by the inline bar and
/// the pinned sidebar.
enum SummaryLoader {
    /// Returns the summary HTML and, for the home summary, the "you were mentioned" block.
    ///
    /// Day summaries are shared and generated once per day: everybody reads that
    /// cached copy rather than each paying for their own. So we PEEK the shared
    /// cache first (an indexed SELECT, no AI) and show the cached summary when it
    /// exists — only generating a fresh one on a cache miss (John's request: use the
    /// cached daily summary, don't recalculate unless necessary).
    static func load(_ kind: SummaryKind, days: Int) async throws -> (html: String, mine: String?) {
        if let cached = try? await fetch(kind, days: days, peek: true),
           let h = cached.summary, !h.isEmpty {
            return (h, (cached.mine?.isEmpty == false) ? cached.mine : nil)
        }
        let r = try await fetch(kind, days: days, peek: false)
        return (r.summary ?? "<p>No activity in this window.</p>", (r.mine?.isEmpty == false) ? r.mine : nil)
    }

    private static func fetch(_ kind: SummaryKind, days: Int, peek: Bool) async throws -> SummaryResult {
        let api = DcampAPI.shared
        switch kind {
        case .home: return try await api.homeSummary(days: days, peek: peek)
        case .forum(let id, _): return try await api.forumSummary(projectID: id, days: days, peek: peek)
        case .thread(let id): return try await api.threadSummary(messageID: id, days: days, peek: peek)
        case .chat: return try await api.chatSummary(days: days, peek: peek)
        }
    }

    /// Day windows offered in the picker (the web allows 1–30; these presets span it).
    static let windows = [1, 2, 3, 5, 7, 10, 14, 21, 30]
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
    @State private var mine: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Menu {
                    ForEach(SummaryLoader.windows, id: \.self) { d in
                        Button(Self.daysLabel(d)) { days = d; if expanded { Task { await reload() } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.daysLabel(days)).font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.dcInkSoft)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.dcPanel, in: Capsule())
                    .overlay(Capsule().stroke(Color.dcLineStrong, lineWidth: 1))
                }
                Button(expanded ? T("Hide") : T("Summarize")) { toggle() }.buttonStyle(DCPrimaryButtonStyle())
                if expanded && hSize == .regular {
                    Button { pinToSidebar() } label: { Label(T("Show in sidebar"), systemImage: "sidebar.left") }
                        .font(.system(size: 13))
                }
                Spacer()
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let mine {   // "you were mentioned" callout (home summary)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(T("You were mentioned"), systemImage: "at.circle.fill")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dcAccentInk)
                            TrixContentView(html: mine).font(.system(size: 14))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dcAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Group {
                        if loading {
                            HStack(spacing: 8) { ProgressView(); Text(T("Summarizing…")).font(.footnote).foregroundStyle(Color.dcMuted) }
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else if let html {
                            TrixContentView(html: html).font(.system(size: 15))
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: DC.radius))
                .overlay(RoundedRectangle(cornerRadius: DC.radius).stroke(Color.dcLine, lineWidth: 1))
            }
        }
    }

    /// Localized "past N days" label. Uses a `{n}` template (like the web's `tn`)
    /// so the number's position is chosen by the translation, not hard-coded.
    static func daysLabel(_ d: Int) -> String {
        let tmpl = d == 1 ? T("past {n} day") : T("past {n} days")
        return tmpl.replacingOccurrences(of: "{n}", with: "\(d)")
    }

    private func toggle() {
        if expanded { expanded = false } else { expanded = true; Task { await reload() } }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        if let r = try? await SummaryLoader.load(kind, days: days) { html = r.html; mine = r.mine }
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
        html = (try? await SummaryLoader.load(kind, days: pin.days))?.html
    }
}

// MARK: - Summaries-by-email page

/// The full "Summaries by email" page: choose sources + frequency, preview the
/// activity digest, email a sample, and toggle the email subscription.
struct EmailSummariesView: View {
    @Environment(SessionStore.self) private var session
    @State private var period = "week"
    @State private var emailEnabled = false
    @State private var selectedSources: Set<String> = []
    @State private var digest: String?
    @State private var loading = false
    @State private var sampleSentAt: Date?
    @State private var loaded = false
    private let api = DcampAPI.shared

    private var sourceOptions: [(String, String)] {
        // The 4 forums (by id) plus the Chat Room, mirroring the web.
        session.boards.filter { $0.kind == nil || $0.kind == "forum" }.map { (String($0.id), $0.name) } + [("chat", T("Chat Room"))]
    }
    private var sourcesCSV: String { selectedSources.sorted().joined(separator: ",") }

    var body: some View {
        Form {
            Section(T("Frequency")) {
                Picker(T("Send me a summary"), selection: $period) {
                    Text(T("Daily")).tag("day"); Text(T("Weekly")).tag("week"); Text(T("Monthly")).tag("month")
                }.pickerStyle(.segmented)
                Toggle(T("Email me summaries"), isOn: $emailEnabled)
                if emailEnabled { Text(signupLabel).font(.caption).foregroundStyle(Color.dcMuted) }
            }
            Section(T("Include")) {
                ForEach(sourceOptions, id: \.0) { id, name in
                    Toggle(name, isOn: Binding(
                        get: { selectedSources.contains(id) },
                        set: { on in if on { selectedSources.insert(id) } else { selectedSources.remove(id) } }
                    ))
                }
            }
            Section {
                Button { Task { await save() } } label: { Text(T("Save summary settings")) }
                Button { Task { await sendSample() } } label: {
                    Label(sampleSentAt == nil ? T("Email me a sample") : T("Sample sent"), systemImage: "paperplane")
                }.disabled(sampleSentAt != nil && Date().timeIntervalSince(sampleSentAt!) < 60)
            }
            Section(T("Preview")) {
                if loading { HStack { ProgressView(); Text(T("Generating…")).foregroundStyle(Color.dcMuted) } }
                else if let d = digest { TrixContentView(html: d).font(.system(size: 14)) }
                else { Button(T("Preview my digest")) { Task { await preview() } } }
            }
        }
        .scrollContentBackground(.hidden).background(Color.dcBg)
        .navigationTitle(T("Summaries by email")).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: period) { _, _ in digest = nil }
    }

    private var signupLabel: String {
        switch period {
        case "day": return T("You’re signed up for daily summaries.")
        case "month": return T("You’re signed up for monthly summaries.")
        default: return T("You’re signed up for weekly summaries.")
        }
    }

    private func load() async {
        guard !loaded else { return }
        let p = await api.summaryPrefsGet()
        period = p.period ?? "week"
        emailEnabled = (p.emailEnabled ?? 0) != 0
        selectedSources = Set((p.sources ?? "").split(separator: ",").map(String.init))
        loaded = true
    }
    private func preview() async {
        loading = true; defer { loading = false }
        digest = (await api.activitySummary(sources: sourcesCSV, period: period)).summary
    }
    private func save() async {
        await api.summaryPrefsSave(sources: sourcesCSV, period: period, emailEnabled: emailEnabled)
    }
    private func sendSample() async {
        await api.summaryEmailSample(sources: sourcesCSV, period: period)
        sampleSentAt = Date()
    }
}
