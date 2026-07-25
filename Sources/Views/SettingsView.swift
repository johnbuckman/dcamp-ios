import SwiftUI

/// My settings — profile, location, notification prefs, summaries-by-email,
/// muted people, Basecamp status, and account actions. Mirrors the web settings.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var about = ""
    @State private var city = ""
    @State private var country = ""
    @State private var showLocation = true

    @State private var popup: Set<String> = []
    @State private var email: Set<String> = []

    @State private var summaryPeriod = "week"
    @State private var summaryEmail = false
    @State private var summarySources = ""   // round-tripped; source picker lives on the web Summaries page

    @State private var muted: [Person] = []
    @State private var loaded = false
    @State private var savingProfile = false
    @State private var showClose = false
    @State private var showHelp = false
    @AppStorage("dcamp_theme") private var themeRaw = ThemeMode.system.rawValue

    private let api = DcampAPI.shared
    private let kinds: [(String, String)] = [
        ("mention", "Mentions"), ("dm", "Direct messages"),
        ("comment_own", "Replies to my threads"), ("comment_followed", "Threads I follow"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                appearanceSection
                locationSection
                notifSection
                summarySection
                if !muted.isEmpty { mutedSection }
                basecampSection
                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.dcBg)
            .navigationTitle("My settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await load() }
            .confirmationDialog("Close your account?", isPresented: $showClose, titleVisibility: .visible) {
                Button("Close account", role: .destructive) { Task { await api.accountClose(); await session.logout(); dismiss() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your posts stay, but you’re removed from search, @mention and the member list. Logging in again reopens it.") }
            .sheet(isPresented: $showHelp) { HelpView() }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            TextField("Display name", text: $name)
            TextField("About you", text: $about, axis: .vertical).lineLimit(2...4)
            Button {
                savingProfile = true
                Task { await api.settingsSave(name: name, about: about, avatarImg: session.me?.avatarImg ?? "", showLocation: showLocation); await session.refresh(); savingProfile = false }
            } label: {
                HStack { if savingProfile { ProgressView() }; Text("Save profile") }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeRaw) {
                ForEach(ThemeMode.allCases) { m in Text(m.label).tag(m.rawValue) }
            }
            .pickerStyle(.segmented)
            .onChange(of: themeRaw) { _, v in
                // Sync to the server so the web and other devices match (web ui-pref "dcamp_theme").
                Task { await api.uiPrefsSave(name: "dcamp_theme", value: ThemeMode(rawValue: v)?.serverValue ?? "") }
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            HStack { Text("City"); Spacer(); TextField("City", text: $city).multilineTextAlignment(.trailing) }
            HStack { Text("Country"); Spacer(); TextField("US", text: $country).multilineTextAlignment(.trailing).frame(width: 80) }
            Toggle("Show my city & country on my profile", isOn: $showLocation)
            Button("Save location") { Task { await api.locationSave(country: country, city: city); await api.settingsSave(name: name, about: about, avatarImg: session.me?.avatarImg ?? "", showLocation: showLocation) } }
        }
    }

    private var notifSection: some View {
        Section {
            ForEach(kinds, id: \.0) { key, label in
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(.subheadline.weight(.medium))
                    HStack(spacing: 18) {
                        Toggle("Popup", isOn: popupBinding(key)).toggleStyle(.button).tint(.dcAccent)
                        Toggle("Email", isOn: emailBinding(key)).toggleStyle(.button).tint(.dcAccent)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
        } header: { Text("Notifications") } footer: { Text("Popups appear in-app and as push. Email for mentions/replies is paused in favour of summaries.") }
    }

    private func popupBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { popup.contains(key) },
                set: { on in if on { popup.insert(key) } else { popup.remove(key) }; savePrefs() })
    }
    private func emailBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { email.contains(key) },
                set: { on in if on { email.insert(key) } else { email.remove(key) }; savePrefs() })
    }
    private func savePrefs() { Task { await api.notifPrefsSave(email: Array(email), popup: Array(popup)) } }

    private var summarySection: some View {
        Section("Summaries by email") {
            Picker("Frequency", selection: $summaryPeriod) {
                Text("Daily").tag("day"); Text("Weekly").tag("week"); Text("Monthly").tag("month")
            }
            Toggle("Email me summaries", isOn: $summaryEmail)
            Button("Save summary settings") {
                Task { await api.summaryPrefsSave(sources: summarySources, period: summaryPeriod, emailEnabled: summaryEmail) }
            }
            NavigationLink { EmailSummariesView().environment(session) } label: {
                Label("Manage sources & email a sample", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var mutedSection: some View {
        Section("Muted people") {
            ForEach(muted) { p in
                HStack {
                    Avatar(person: p, size: 28); Text(p.name)
                    Spacer()
                    Button("Unmute") { Task { await api.personUnmute(id: p.id); muted.removeAll { $0.id == p.id } } }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var basecampSection: some View {
        Section("Basecamp") {
            HStack {
                Text("Account")
                Spacer()
                Text(session.bcLinked ? "Linked" : "Not linked")
                    .foregroundStyle(session.bcLinked ? Color.dcAccentInk : Color.dcMuted)
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button { showHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
            if let me = session.me { LabeledContent("dcamp id", value: "\(me.id)") }
            Button(role: .destructive) { showClose = true } label: { Text("Close account") }
            Button(role: .destructive) { Task { await session.logout(); dismiss() } } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func load() async {
        guard !loaded else { return }
        name = session.me?.name ?? ""
        about = session.me?.about ?? ""
        let loc = await api.locationGet()
        city = loc.city ?? ""; country = loc.countryCode ?? ""; showLocation = (loc.showLocation ?? 1) != 0
        let prefs = (try? await api.notifPrefsGet()) ?? NotifPrefs()
        popup = Set(prefs.popup); email = Set(prefs.email)
        let sp = await api.summaryPrefsGet()
        summaryPeriod = sp.period ?? "week"; summaryEmail = (sp.emailEnabled ?? 0) != 0
        summarySources = sp.sources ?? ""
        muted = await api.personMutes()
        loaded = true
    }
}
