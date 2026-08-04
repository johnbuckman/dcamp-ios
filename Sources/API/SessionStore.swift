import SwiftUI
import UIKit
import AuthenticationServices

/// App-wide session + bootstrap state. Drives the login gate and holds the
/// board list. `@Observable` so SwiftUI views update automatically.
@MainActor
@Observable
final class SessionStore {
    enum Phase { case launching, loggedOut, loggedIn }

    var phase: Phase = .launching
    var me: Person?
    var boards: [Board] = []
    var categories: [Category] = []
    var canPost = false
    var isAdmin = false
    var bcLinked = false
    var showRegions = false
    var showRoasters = false
    var pingUnread = 0
    var chatUnread = 0
    var lang = "en"

    var loggingIn = false
    var errorMessage: String?

    private let api = DcampAPI.shared

    static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "ios-unknown"
    }

    /// Called once on launch: resume a saved token or show the login screen.
    func start() async {
        #if DEBUG
        // Screenshot harness: force a UI language (seeds the X-Dcamp-Lang header pref).
        if let l = ProcessInfo.processInfo.environment["DCAMP_LANG"] {
            UserDefaults.standard.set(l, forKey: "dcamp_lang")
        }
        // Screenshot harness: force the logged-out login screen even if a token is cached.
        if ProcessInfo.processInfo.environment["DCAMP_SHOT_SCREEN"] == "login" { phase = .loggedOut; return }
        #endif
        #if DEBUG
        // Env-gated smoke test: lets a headless launch exercise the real
        // network+auth path (auth_token → bootstrap) without GUI login. Never
        // fires unless DCAMP_SMOKE_EMAIL is set. Safe to leave in DEBUG builds.
        let env = ProcessInfo.processInfo.environment
        if let em = env["DCAMP_SMOKE_EMAIL"], let pw = env["DCAMP_SMOKE_PW"] {
            // Headless auto-login uses the email/pw token mint directly (there's no
            // browser in a smoke run). Production sign-in is browser-only (OAuth).
            loggingIn = true
            do { try await api.login(email: em, password: pw, deviceID: Self.deviceID); await loadBootstrap() }
            catch { errorMessage = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription }
            loggingIn = false
            FileHandle.standardError.write(Data(
                "SMOKE result phase=\(phase) boards=\(boards.count) me=\(me?.name ?? "nil") canPost=\(canPost) err=\(errorMessage ?? "none")\n".utf8))
            if let mid = env["DCAMP_SMOKE_MSG"] {
                await smokeParse(messageID: mid)
            }
            if env["DCAMP_SMOKE_NOTIF"] != nil {
                await api.pushRegister(token: "a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899", platform: "apns")
                let notifs = (try? await api.notifPoll()) ?? []
                let first = notifs.first
                FileHandle.standardError.write(Data(
                    "SMOKE notif count=\(notifs.count) firstKind=\(first?.kind ?? "-") route=\(first?.route ?? "-") msgID=\(DcampRoute.messageID(from: first?.route).map(String.init) ?? "-")\n".utf8))
            }
            if env["DCAMP_SMOKE_M56"] != nil {
                let chat = (try? await api.chatLines())?.lines.count ?? -1
                let convos = (try? await api.dmConversations())?.conversations ?? []
                var dmMsgs = -1
                if let first = convos.first { dmMsgs = (try? await api.dmThread(convoID: first.id))?.messages.count ?? -1 }
                let s = try? await api.search("milk")
                let card = try? await api.personCard(id: 1)
                let ui = (try? await api.uiMap())?.count ?? -1
                FileHandle.standardError.write(Data(
                    "SMOKE m56 chatLines=\(chat) dmConvos=\(convos.count) dmMsgs=\(dmMsgs) searchResults=\(s?.results.count ?? -1) searchPeople=\(s?.people.count ?? -1) card=\(card?.person.name ?? "-")/msgs=\(card?.messages.count ?? -1) uiMap=\(ui)\n".utf8))
            }
            if let postTo = env["DCAMP_SMOKE_POST"], let mid = Int(postTo) {
                do {
                    let r = try await api.createComment(messageID: mid, bodyHTML: "<p>Native <strong>client</strong> smoke reply.</p>")
                    FileHandle.standardError.write(Data("SMOKE post comment ok id=\(r.id ?? -1) err=\(r.error ?? "none")\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("SMOKE post error: \(error)\n".utf8))
                }
            }
            return
        }
        #endif
        if await api.isAuthenticated {
            // On launch a bootstrap failure means the SAVED token is stale → log out.
            if !(await loadBootstrap()) {
                await api.setToken(nil)
                phase = .loggedOut
            }
        } else {
            phase = .loggedOut
        }
    }

    #if DEBUG
    /// Smoke: fetch a real thread, run it through TrixParser, print a block
    /// summary so the native renderer can be verified headlessly.
    private func smokeParse(messageID: String) async {
        do {
            let resp: MessageResponse = try await api.call("message", ["id": messageID])
            let blocks = TrixParser.parse(resp.message.html)
            let kinds = blocks.map { b -> String in
                switch b {
                case .paragraph: return "p"
                case .heading(_, let l): return "h\(l)"
                case .quote: return "quote"
                case .list(let i, let o): return "\(o ? "ol" : "ul")(\(i.count))"
                case .image: return "img"
                case .youtube: return "yt"
                case .table(let r): return "table(\(r.count)x\(r.first?.count ?? 0))"
                case .rule: return "hr"
                }
            }
            FileHandle.standardError.write(Data(
                "SMOKE parse msg=\(messageID) subject=\"\(resp.message.displaySubject.prefix(40))\" comments=\(resp.comments?.count ?? 0) blocks=[\(kinds.joined(separator: ","))]\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("SMOKE parse error: \(error)\n".utf8))
        }
    }
    #endif

    /// Browser sign-in (OAuth2 + PKCE). The password never touches the app.
    func loginWithBrowser() async {
        errorMessage = nil
        loggingIn = true
        defer { loggingIn = false }
        do {
            let result = try await OAuthService.shared.authorize()
            try await api.exchangeOAuth(code: result.code, verifier: result.verifier, deviceID: Self.deviceID)
            // The token is valid now. A first bootstrap can transiently fail while the
            // auth sheet is still dismissing (the "blank screen, worked on retry" bug);
            // retry once and NEVER drop the freshly-minted token — no full re-login.
            if !(await loadBootstrap()) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !(await loadBootstrap()) {
                    errorMessage = errorMessage ?? T("Signed in, but couldn’t load the forum. Pull to refresh.")
                }
            }
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // User dismissed the browser sheet — not an error.
        } catch {
            errorMessage = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
        }
    }

    /// Load the bootstrap payload into session state. Returns whether it succeeded;
    /// the CALLER decides what a failure means (launch → drop stale token; post-login
    /// → keep the valid token and retry). Never drops the token itself.
    @discardableResult
    func loadBootstrap() async -> Bool {
        do {
            let b: Bootstrap = try await api.call("bootstrap")
            me = b.me
            boards = b.projects
            categories = b.categories ?? []
            canPost = b.canPostBool
            isAdmin = b.admin
            bcLinked = b.bcLinkedBool
            showRegions = (b.showRegions ?? 0) != 0
            showRoasters = (b.showRoasters ?? 0) != 0
            pingUnread = b.pingUnread ?? 0
            chatUnread = b.chatUnread ?? 0
            lang = b.lang ?? "en"
            // Adopt the member's server-stored appearance (cross-device sync).
            if let t = b.dcampTheme {
                UserDefaults.standard.set(ThemeMode.from(t).rawValue, forKey: "dcamp_theme")
            }
            phase = .loggedIn
            return true
        } catch {
            errorMessage = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
            return false
        }
    }

    func refresh() async {
        _ = await loadBootstrap()
    }

    /// Switch which server the app talks to (admin-only, from My Settings). The
    /// OAuth endpoint differs per server, so the current bearer token is invalid on
    /// the other one — revoke it on the CURRENT server first, THEN flip, landing on
    /// the login screen so the next sign-in goes to the newly selected server.
    func switchServer(local: Bool) async {
        guard local != AppConfig.useLocalDev else { return }
        await logout()                     // revoke + clear on the current server → .loggedOut
        AppConfig.setUseLocalDev(local)     // subsequent apiURL / OAuth URLs now point at the new server
    }

    func logout() async {
        // Detach this device from push + clear the badge BEFORE dropping the token,
        // so the server stops delivering notifications to a signed-out device.
        await PushManager.shared.unregisterToken()
        await PushManager.shared.clearBadge()
        await api.logout()
        me = nil
        boards = []
        categories = []
        canPost = false
        isAdmin = false
        bcLinked = false
        pingUnread = 0
        chatUnread = 0
        phase = .loggedOut
    }
}
