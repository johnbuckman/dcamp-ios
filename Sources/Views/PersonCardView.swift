import SwiftUI

/// A person's profile: identity + machine + location + recent activity. Presented
/// as a sheet when a mention or avatar is tapped.
struct PersonCardView: View {
    let personID: Int

    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var card: PersonCard?
    @State private var loading = false
    private let api = DcampAPI.shared

    var body: some View {
        NavigationStack {
            Group {
                if let card {
                    List {
                        Section { header(card) }
                        Section { actionButtons(card) }
                        if !card.messages.isEmpty {
                            Section("Threads") {
                                ForEach(card.messages) { m in
                                    Button { open(messageID: m.id) } label: {
                                        activityRow(m.subject ?? "Thread", m.createdAt)
                                    }
                                }
                            }
                        }
                        if !card.comments.isEmpty {
                            Section("Comments") {
                                ForEach(card.comments) { c in
                                    Button { open(messageID: c.messageId ?? c.id) } label: {
                                        activityRow(c.messageSubject ?? PlainText.strip(c.body ?? "Comment"), c.createdAt)
                                    }
                                }
                            }
                        }
                    }
                } else if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView("Couldn’t load profile", systemImage: "person.slash")
                }
            }
            .navigationTitle(card?.person.name ?? "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task { await load() }
    }

    @State private var muted = false
    @State private var reporting = false
    @State private var reportReason = ""

    @ViewBuilder private func actionButtons(_ card: PersonCard) -> some View {
        Button {
            Task {
                if let convo = try? await api.dmDirect(personID: card.person.id) {
                    dismiss(); router.dmID = convo
                }
            }
        } label: { Label("Message", systemImage: "envelope") }

        Button {
            Task {
                if muted { await api.personUnmute(id: card.person.id) } else { await api.personMute(id: card.person.id) }
                muted.toggle()
            }
        } label: { Label(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.wave.2" : "speaker.slash") }

        Button(role: .destructive) { reporting = true } label: { Label("Report", systemImage: "flag") }
            .alert("Report \(card.person.name)?", isPresented: $reporting) {
                TextField("Reason", text: $reportReason)
                Button("Report", role: .destructive) {
                    Task { await api.reportPerson(id: card.person.id, reason: reportReason, url: "app://person/\(card.person.id)"); reportReason = "" }
                }
                Button("Cancel", role: .cancel) { reportReason = "" }
            } message: { Text("This alerts the moderators.") }
    }

    private func header(_ card: PersonCard) -> some View {
        HStack(spacing: 14) {
            Avatar(person: card.person, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.person.name).font(.title3.bold())
                if let m = card.person.machine, !m.isEmpty {
                    Label(m, systemImage: "cup.and.saucer").font(.caption).foregroundStyle(.secondary)
                }
                if let city = card.city, !city.isEmpty {
                    Label(city, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                }
                if let about = card.person.about, !about.isEmpty {
                    Text(about).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func activityRow(_ title: String, _ epoch: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
            Text(RelativeTime.string(epoch)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func open(messageID: Int) {
        dismiss()
        router.threadID = messageID
    }

    private func load() async {
        loading = true; defer { loading = false }
        card = try? await api.personCard(id: personID)
        muted = (card?.muted ?? 0) != 0
    }
}
