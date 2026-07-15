import SwiftUI

/// Top-level gate: launching → login → main. Driven by `SessionStore.phase`.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        content
            .tint(Color.dcAccent)
            .preferredColorScheme(.light)   // dcamp web is light-only ("warm paper")
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
