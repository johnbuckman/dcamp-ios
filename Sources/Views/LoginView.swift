import SwiftUI

/// Native email + password login. Mints a bearer token via `auth_token`.
struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Color.dcBg.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack(spacing: 9) {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 22)).foregroundStyle(Color.dcInk)
                    Text("dcamp").font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                }

                VStack(spacing: 6) {
                    Text("Welcome to the Decent Diaspora")
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(Color.dcInk)
                        .multilineTextAlignment(.center)
                    Text("Log in with your existing Decent support account.")
                        .font(.system(size: 15)).foregroundStyle(Color.dcInkSoft)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    field(label: "Email address") {
                        TextField("", text: $email)
                            .textContentType(.username).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    }
                    field(label: "Password") {
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password).submitLabel(.go).onSubmit(submit)
                    }

                    if let msg = session.errorMessage {
                        Text(msg).font(.system(size: 13)).foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        HStack {
                            if session.loggingIn { ProgressView().tint(.white) }
                            Text(session.loggingIn ? "Signing in…" : "Continue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DCPrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .padding(.top, 4)
                }
            }
            .padding(30)
            .frame(maxWidth: 400)
            .dcCard(padding: 0)
            .padding(20)
        }
        .onAppear { focus = .email }
    }

    @ViewBuilder private func field<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dcInkSoft)
            content()
                .font(.system(size: 16))
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(Color.dcPanel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dcLineStrong, lineWidth: 1))
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !session.loggingIn
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task { await session.login(email: email, password: password) }
    }
}
