import SwiftUI

/// Browser sign-in. The app never handles the password — it opens the
/// /support/oauth2 authorize page in a system browser; an already-logged-in
/// member signs in with one tap (shared Safari cookie). Admin status is captured
/// server-side and baked into the returned token.
struct LoginView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Color.dcBg.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack(spacing: 9) {
                    // Same DE1 espresso-machine mark as the app top bar (not a coffee cup).
                    Image("DcampMark").resizable().aspectRatio(contentMode: .fit).frame(height: 30)
                    Text(T("dcamp")).font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                }

                VStack(spacing: 6) {
                    Text(T("Welcome to the Decent Diaspora"))
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                        .multilineTextAlignment(.center)
                    Text(T("Sign in with your existing Decent support account."))
                        .font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    if let msg = session.errorMessage {
                        Text(msg).font(.system(size: 13)).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await session.loginWithBrowser() }
                    } label: {
                        HStack(spacing: 8) {
                            if session.loggingIn { ProgressView().tint(.white) }
                            else { Image(systemName: "safari") }
                            Text(session.loggingIn ? "Signing in…" : "Sign in with Decent")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DCPrimaryButtonStyle())
                    .disabled(session.loggingIn)

                    Text(T("Opens a secure browser. Your password is never entered in the app."))
                        .font(.system(size: 12)).foregroundStyle(Color.dcMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(30)
            .frame(maxWidth: 400)
            .dcCard(padding: 0)
            .padding(20)
        }
    }
}
