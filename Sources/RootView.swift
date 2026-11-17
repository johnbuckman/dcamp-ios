import SwiftUI

/// Top-level gate: launching → login → main. Driven by `SessionStore.phase`.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var sharedToConvo: Int?   // DM picked for a shared link; opened on dismiss
    @AppStorage("dcamp_theme") private var themeRaw = ThemeMode.system.rawValue

    var body: some View {
        content
            .tint(Color.dcAccent)
            .preferredColorScheme(ThemeMode(rawValue: themeRaw)?.colorScheme)
            .environment(\.layoutDirection, session.lang == "ar" ? .rightToLeft : .leftToRight)
            // "Send link to…" for a link shared from another app. Hosted here, not in
            // MainView, so it also appears when logged out (it then offers only Log in).
            .sheet(item: shareSheet, onDismiss: {
                // open the DM AFTER the sheet is gone (gotcha 7); MainView pushes it
                if let c = sharedToConvo { sharedToConvo = nil; router.dmID = c }
            }) { link in
                ShareToDMView(link: link) { sharedToConvo = $0 }
                    .environment(session).environment(router)
                    .tint(Color.dcAccent)
            }
    }

    private var shareSheet: Binding<SharedLink?> {
        Binding(get: { router.pendingShare }, set: { router.pendingShare = $0 })
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .launching:
            ZStack { Color.dcBg.ignoresSafeArea(); ProgressView().controlSize(.large) }
        case .loggedOut:
            LoginView()
        case .loggedIn:
            MainView()
        }
    }
}
