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
            do { try await api.login(email: em, password: pw, deviceID: Self.deviceID); await loadBootstrap(initial: true) }
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
                let convos = (try? await api.dmConversations()) ?? []
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
            await loadBootstrap(initial: true)
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
            await loadBootstrap(initial: true)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // User dismissed the browser sheet — not an error.
        } catch {
            errorMessage = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
        }
    }

    func loadBootstrap(initial: Bool) async {
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
            lang = b.lang ?? "en"
            // Adopt the member's server-stored appearance on login (cross-device sync).
            if initial, let t = b.dcampTheme {
                UserDefaults.standard.set(ThemeMode.from(t).rawValue, forKey: "dcamp_theme")
            }
            phase = .loggedIn
        } catch {
            // A stale/invalid token on launch → fall back to the login screen.
            if initial {
                await api.setToken(nil)
                phase = .loggedOut
            } else {
                errorMessage = (error as? DcampAPI.APIError)?.message ?? error.localizedDescription
            }
        }
    }

    func refresh() async {
        await loadBootstrap(initial: false)
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
        phase = .loggedOut
    }
}
