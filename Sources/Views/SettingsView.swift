import SwiftUI
import PhotosUI

/// My settings — profile, location, notification prefs, summaries-by-email,
/// muted people, Basecamp status, and account actions. Mirrors the web settings.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var about = ""
    @State private var avatarImg = ""            // current avatar URL (updated by the picker)
    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var avatarError: String?
    @State private var city = ""
    @State private var country = ""
    @State private var showLocation = true

    @State private var popup: Set<String> = []
    @State private var email: Set<String> = []

    @State private var summaryPeriod = "week"
    @State private var summaryEmail = false
    @State private var summarySources = ""   // round-tripped; source picker lives on the web Summaries page

    @State private var muted: [Person] = []
    @State private var pendingServerLocal: Bool?   // admin server switch, awaiting confirm
    @State private var loaded = false
    @State private var savingProfile = false
    @State private var showClose = false
    @State private var showHelp = false
    @AppStorage("dcamp_theme") private var themeRaw = ThemeMode.system.rawValue
    @AppStorage("dcamp_lang") private var langPref = ""
    @Environment(UIStrings.self) private var strings

    private let api = DcampAPI.shared
    private var kinds: [(String, String)] {
        [("mention", T("Mentions")), ("dm", T("Direct messages")),
         ("comment_own", T("Replies to my threads")), ("comment_followed", T("Threads I follow"))]
    }

    var body: some View {
        NavigationStack {
            Form {
                if session.isAdmin { serverSection }
                profileSection
                appearanceSection
                languageSection
                locationSection
                notifSection
                summarySection
                if !muted.isEmpty { mutedSection }
                basecampSection
                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.dcBg)
            .navigationTitle(T("My settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(T("Done")) { dismiss() } } }
            .task { await load() }
            .confirmationDialog(T("Close your account?"), isPresented: $showClose, titleVisibility: .visible) {
                Button(T("Close account"), role: .destructive) { Task { await api.accountClose(); await session.logout(); dismiss() } }
                Button(T("Cancel"), role: .cancel) {}
            } message: { Text(T("Your posts stay, but you’re removed from search, @mention and the member list. Logging in again reopens it.")) }
            .alert(T("Couldn’t update your photo"), isPresented: Binding(get: { avatarError != nil }, set: { if !$0 { avatarError = nil } })) {
                Button(T("OK")) { avatarError = nil }
            } message: { Text(avatarError ?? "") }
            .sheet(isPresented: $showHelp) { HelpView() }
        }
    }

    // Admin-only: point the app at the Live (decentespresso.com) or Test
    // (localhost:8000) server. Switching signs you out — the OAuth endpoint differs
    // per server, so you sign in again on the one you pick.
    private var serverSection: some View {
        Section {
            Picker(T("Server"), selection: Binding(
                get: { AppConfig.useLocalDev },
                set: { wantLocal in if wantLocal != AppConfig.useLocalDev { pendingServerLocal = wantLocal } }
            )) {
                Text(T("Live")).tag(false)
                Text(T("Test")).tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(T("Server"))
        } footer: {
            Text(T("Now using") + " " + AppConfig.serverLabel + ". " + T("Switching signs you out; you'll sign in again on the selected server."))
        }
        .confirmationDialog(T("Switch server?"),
                            isPresented: Binding(get: { pendingServerLocal != nil }, set: { if !$0 { pendingServerLocal = nil } }),
                            titleVisibility: .visible) {
            if let want = pendingServerLocal {
                Button(want ? T("Switch to Test (localhost:8000)") : T("Switch to Live (decentespresso.com)")) {
                    Task { await session.switchServer(local: want); pendingServerLocal = nil; dismiss() }
                }
                Button(T("Cancel"), role: .cancel) { pendingServerLocal = nil }
            }
        } message: {
            Text(T("You'll be signed out and need to sign in again on the selected server."))
        }
    }

    private var profileSection: some View {
        Section(T("Profile")) {
            HStack(spacing: 14) {
                avatarPreview
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    HStack(spacing: 6) {
                        if uploadingAvatar { ProgressView() }
                        Text(uploadingAvatar ? T("Uploading…") : T("Change photo"))
                    }
                }
                .disabled(uploadingAvatar)
            }
            TextField(T("Display name"), text: $name)
            TextField(T("About you"), text: $about, axis: .vertical).lineLimit(2...4)
            Button {
                savingProfile = true
                Task { await api.settingsSave(name: name, about: about, avatarImg: avatarImg, showLocation: showLocation); await session.refresh(); savingProfile = false }
            } label: {
                HStack { if savingProfile { ProgressView() }; Text(T("Save profile")) }
            }
        }
        .onChange(of: avatarItem) { _, item in if let item { Task { await uploadAvatar(item) } } }
    }

    @ViewBuilder private var avatarPreview: some View {
        // Show the just-picked/current avatar. Reuse Avatar via a display-only Person.
        Avatar(person: Person(id: session.me?.id ?? 0, name: name.isEmpty ? (session.me?.name ?? "") : name,
                              avatarColor: session.me?.avatarColor, avatarImg: avatarImg.isEmpty ? nil : avatarImg,
                              initials: session.me?.initials), size: 56)
    }

    /// Upload the picked image, point the profile at it, and persist immediately
    /// (the web treats avatar_img as an overwrite, so we save the real new URL).
    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarError = T("Couldn’t read that photo. Try a different one."); return
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let url = try await api.uploadImage(data, filename: "avatar.\(ext)", mime: mime)
            avatarImg = url
            await api.settingsSave(name: name, about: about, avatarImg: avatarImg, showLocation: showLocation)
            await session.refresh()
        } catch {
            // Surface the reason instead of failing silently (John: "avatar change
            // doesn't work" — with no error it's impossible to tell what went wrong).
            avatarError = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
        }
    }

    private func themeLabel(_ m: ThemeMode) -> String {
        switch m { case .system: return T("System"); case .light: return T("Light"); case .dark: return T("Dark") }
    }

    private var appearanceSection: some View {
        Section(T("Appearance")) {
            Picker(T("Theme"), selection: $themeRaw) {
                ForEach(ThemeMode.allCases) { m in Text(themeLabel(m)).tag(m.rawValue) }
            }
            .pickerStyle(.segmented)
            .onChange(of: themeRaw) { _, v in
                // Sync to the server so the web and other devices match (web ui-pref "dcamp_theme").
                Task { await api.uiPrefsSave(name: "dcamp_theme", value: ThemeMode(rawValue: v)?.serverValue ?? "") }
            }
        }
    }

    private var languageSection: some View {
        Section(T("Language")) {
            Picker(T("Language"), selection: $langPref) {
                ForEach(AppLanguage.all) { l in Text(l.name).tag(l.code) }
            }
            .onChange(of: langPref) { _, _ in
                // The X-Dcamp-Lang header now reads the new value; re-hydrate content + UI strings.
                Task {
                    await session.refresh()
                    strings.lang = session.lang
                    await strings.load()
                }
            }
            Text(T("Content and the interface appear in your language. Interface translations arrive as they’re added on the server."))
                .font(.caption).foregroundStyle(Color.dcMuted)
        }
    }

    private var locationSection: some View {
        Section(T("Location")) {
            HStack { Text(T("City")); Spacer(); TextField(T("City"), text: $city).multilineTextAlignment(.trailing) }
            HStack { Text(T("Country")); Spacer(); TextField(T("US"), text: $country).multilineTextAlignment(.trailing).frame(width: 80) }
            Toggle(T("Show my city & country on my profile"), isOn: $showLocation)
            Button(T("Save location")) { Task { await api.locationSave(country: country, city: city); await api.settingsSave(name: name, about: about, avatarImg: avatarImg, showLocation: showLocation) } }
        }
    }

    private var notifSection: some View {
        Section {
            ForEach(kinds, id: \.0) { key, label in
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(.subheadline.weight(.medium))
                    HStack(spacing: 18) {
                        Toggle(T("Popup"), isOn: popupBinding(key)).toggleStyle(.button).tint(.dcAccent)
                        Toggle(T("Email"), isOn: emailBinding(key)).toggleStyle(.button).tint(.dcAccent)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
        } header: { Text(T("Notifications")) } footer: { Text(T("Popups appear in-app and as push. Email for mentions/replies is paused in favour of summaries.")) }
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
        Section(T("Summaries by email")) {
            Picker(T("Frequency"), selection: $summaryPeriod) {
                Text(T("Daily")).tag("day"); Text(T("Weekly")).tag("week"); Text(T("Monthly")).tag("month")
            }
            Toggle(T("Email me summaries"), isOn: $summaryEmail)
            Button(T("Save summary settings")) {
                Task { await api.summaryPrefsSave(sources: summarySources, period: summaryPeriod, emailEnabled: summaryEmail) }
            }
            NavigationLink { EmailSummariesView().environment(session) } label: {
                Label(T("Manage sources & email a sample"), systemImage: "slider.horizontal.3")
            }
        }
    }

    private var mutedSection: some View {
        Section(T("Muted people")) {
            ForEach(muted) { p in
                HStack {
                    Avatar(person: p, size: 28); Text(p.name)
                    Spacer()
                    Button(T("Unmute")) { Task { await api.personUnmute(id: p.id); muted.removeAll { $0.id == p.id } } }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var basecampSection: some View {
        Section(T("Basecamp")) {
            HStack {
                Text(T("Account"))
                Spacer()
                Text(session.bcLinked ? T("Linked") : T("Not linked"))
                    .foregroundStyle(session.bcLinked ? Color.dcAccentInk : Color.dcMuted)
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button { showHelp = true } label: { Label(T("Help"), systemImage: "questionmark.circle") }
            if let me = session.me { LabeledContent(T("dcamp id"), value: "\(me.id)") }
            Button(role: .destructive) { showClose = true } label: { Text(T("Close account")) }
            Button(role: .destructive) { Task { await session.logout(); dismiss() } } label: {
                Label(T("Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func load() async {
        guard !loaded else { return }
        name = session.me?.name ?? ""
        about = session.me?.about ?? ""
        avatarImg = session.me?.avatarImg ?? ""
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
