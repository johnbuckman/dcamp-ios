import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Drives the browser sign-in flow: builds a PKCE Authorization-Code request,
/// opens the /support/oauth2 authorize page in `ASWebAuthenticationSession`
/// (which shares Safari's cookies, so an already-logged-in member gets one-tap
/// SSO), and returns the auth code + PKCE verifier from the `dcamp://auth` callback.
@MainActor
final class OAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthService()
    private var current: ASWebAuthenticationSession?

    struct AuthResult { let code: String; let verifier: String }
    enum OAuthError: LocalizedError {
        case cannotStart, badCallback
        var errorDescription: String? {
            switch self { case .cannotStart: return "Couldn’t open sign-in."; case .badCallback: return "Sign-in didn’t complete." }
        }
    }

    func authorize() async throws -> AuthResult {
        let verifier = Self.randomURLSafe(32)
        let challenge = Self.s256Challenge(verifier)
        let state = Self.randomURLSafe(16)

        var comps = URLComponents(string: AppConfig.oauthAuthorizeURL)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: AppConfig.oauthClientID),
            .init(name: "redirect_uri", value: AppConfig.oauthRedirectURI),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = comps.url else { throw OAuthError.cannotStart }

        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: AppConfig.oauthRedirectScheme) { callback, error in
                if let error { cont.resume(throwing: error); return }
                guard let callback,
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
                      items.first(where: { $0.name == "state" })?.value == state else {
                    cont.resume(throwing: OAuthError.badCallback); return
                }
                cont.resume(returning: AuthResult(code: code, verifier: verifier))
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false   // share Safari cookies → SSO
            self.current = session
            if !session.start() { cont.resume(throwing: OAuthError.cannotStart) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }

    // MARK: PKCE
    static func randomURLSafe(_ bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Data(buf).base64URLEncoded()
    }
    static func s256Challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension Data {
    /// RFC 4648 base64url without padding (the PKCE / JOSE alphabet).
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
