import Foundation

/// Single typed async client for dcamp's `api.adp?action=…` endpoint.
///
/// Native identity is a bearer token (see lib/dcamp_native.tcl) — NOT the
/// /support cookie — so this session deliberately runs cookie-less. Every call
/// carries `client=native` so the server may add native-only fields.
actor DcampAPI {
    static let shared = DcampAPI()

    private var token: String?
    private let session: URLSession
    private let decoder: JSONDecoder

    struct APIError: LocalizedError {
        let message: String
        let code: String?
        var errorDescription: String? { message }
    }

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.waitsForConnectivity = false
        // Upper bound only — each request sets its own timeoutInterval below (the
        // shorter of the two wins), so normal calls stay snappy while AI actions get
        // the full window.
        cfg.timeoutIntervalForRequest = 120
        session = URLSession(configuration: cfg)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        token = KeychainStore.loadToken()
    }

    var isAuthenticated: Bool { token != nil }

    func setToken(_ t: String?) {
        token = t
        if let t { KeychainStore.saveToken(t) } else { KeychainStore.clearToken() }
    }

    // MARK: - Auth

    /// Verify email+pw, mint & persist a bearer token. Runs logged-out (no token).
    @discardableResult
    func login(email: String, password: String, deviceID: String) async throws -> String {
        let data = try await rawData("auth_token", [
            "email": email, "pw": password,
            "device_id": deviceID, "platform": "ios",
        ])
        let resp = try decode(TokenResponse.self, from: data, action: "auth_token")
        guard let tok = resp.token, !tok.isEmpty else {
            throw APIError(message: resp.error ?? "Login failed", code: nil)
        }
        setToken(tok)
        return tok
    }

    func logout() async {
        _ = try? await rawData("token_revoke", [:])
        setToken(nil)
    }

    /// Exchange an OAuth authorization code (+ PKCE verifier) for a bearer token at
    /// the /support/oauth2/token endpoint. Persists the token; returns is_admin.
    @discardableResult
    func exchangeOAuth(code: String, verifier: String, deviceID: String) async throws -> Bool {
        guard let url = URL(string: AppConfig.oauthTokenURL) else {
            throw APIError(message: "Bad token URL", code: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": AppConfig.oauthRedirectURI,
            "client_id": AppConfig.oauthClientID,
            "device_id": deviceID,
        ]
        req.httpBody = params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        struct R: Codable { var ok: Bool?; var accessToken: String?; var isAdmin: Int?; var error: String? }
        let r = try decoder.decode(R.self, from: data)
        guard let tok = r.accessToken, !tok.isEmpty else {
            throw APIError(message: r.error ?? "Sign-in failed", code: nil)
        }
        setToken(tok)
        return (r.isAdmin ?? 0) != 0
    }

    // MARK: - Posting

    /// Create a new thread. Returns (id, slug).
    func createMessage(projectID: Int, categoryID: Int, subject: String, bodyHTML: String) async throws -> CreateResult {
        try await call("message_create", [
            "project_id": String(projectID),
            "category_id": String(categoryID),
            "subject": subject,
            "body": bodyHTML,
        ])
    }

    /// Add a comment to a thread. Returns the new comment id.
    func createComment(messageID: Int, bodyHTML: String) async throws -> CreateResult {
        try await call("comment_create", [
            "message_id": String(messageID),
            "body": bodyHTML,
        ])
    }

    /// Toggle a reaction. `type` is "message" | "comment" | "chat".
    func boostToggle(type: String, id: Int, emoji: String) async throws {
        _ = try await rawData("boost_toggle", ["parent_type": type, "parent_id": String(id), "content": emoji])
    }

    // MARK: - Notifications

    func notifPoll() async throws -> [Notif] {
        let r: NotifPollResult = try await call("notif_poll")
        return r.items
    }

    func notifSeen(ids: [Int]) async {
        guard !ids.isEmpty else { return }
        _ = try? await rawData("notif_seen", ["ids": ids.map(String.init).joined(separator: ",")])
    }

    func notifPrefsGet() async throws -> NotifPrefs {
        try await call("notif_prefs_get")
    }

    func notifPrefsSave(email: [String], popup: [String]) async {
        _ = try? await rawData("notif_prefs_save", [
            "email": email.joined(separator: ","),
            "popup": popup.joined(separator: ","),
        ])
    }

    // MARK: - Chat

    func chatLines(room: String = "main", since: Int = 0) async throws -> ChatResponse {
        try await call("chat", ["room": room, "since": String(since)])
    }

    func chatPost(room: String = "main", bodyHTML: String) async throws {
        _ = try await rawData("chat_post", ["room": room, "body": bodyHTML])
    }

    // MARK: - Direct messages

    func dmConversations() async throws -> [DMConversation] {
        struct R: Codable { var conversations: [DMConversation] = [] }
        let r: R = try await call("dm_conversations")
        return r.conversations
    }

    func dmThread(convoID: Int, limit: Int = 40) async throws -> DMThread {
        try await call("dm_thread", ["id": String(convoID), "limit": String(limit)])
    }

    func dmSend(convoID: Int, bodyHTML: String) async throws {
        _ = try await rawData("dm_send", ["convo": String(convoID), "body": bodyHTML])
    }

    func dmCreate(participantIDs: [Int]) async throws -> Int {
        struct R: Codable { var id: Int?; var error: String? }
        let r: R = try await call("dm_create", ["participants": participantIDs.map(String.init).joined(separator: ",")])
        guard let id = r.id else { throw APIError(message: r.error ?? "Couldn’t start conversation", code: nil) }
        return id
    }

    func dmUnread() async -> Int {
        struct R: Codable { var unread: Int? }
        let r: R? = try? await call("dm_unread")
        return r?.unread ?? 0
    }

    func pingRecipients(query: String) async throws -> [Recipient] {
        let r: RecipientsResult = try await call("ping_recipients", ["q": query])
        return r.recipients
    }

    // MARK: - Search & people

    func search(_ query: String, types: String = "messages,comments,chat", years: Int = 0) async throws -> SearchResponse {
        try await call("search", ["q": query, "types": types, "years": String(years)])
    }

    func personCard(id: Int) async throws -> PersonCard {
        try await call("person_card", ["id": String(id)])
    }

    func mentionSearch(_ query: String) async throws -> [Person] {
        struct R: Codable { var people: [Person]?; var results: [Person]? }
        let r: R = try await call("mention_search", ["q": query])
        return r.people ?? r.results ?? []
    }

    // MARK: - i18n

    func uiMap() async throws -> [String: String] {
        struct R: Codable { var map: [String: String]? }
        let r: R = try await call("ui_map")
        return r.map ?? [:]
    }

    // MARK: - Push registration

    func pushRegister(token: String, platform: String = "apns") async {
        _ = try? await rawData("push_register", ["token": token, "platform": platform])
    }

    func pushUnregister(token: String) async {
        _ = try? await rawData("push_unregister", ["token": token])
    }

    /// Upload an attachment (multipart). Returns the server URL to embed.
    func uploadImage(_ data: Data, filename: String, mime: String) async throws -> String {
        let boundary = "dcamp-\(UUID().uuidString)"
        var req = URLRequest(url: AppConfig.apiURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 120   // photos can be large; don't cut the upload short
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func part(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (k, v) in ["action": "upload", "client": AppConfig.nativeClient] {
            part("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        part("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        part("\r\n--\(boundary)--\r\n")

        let (respData, resp) = try await session.upload(for: req, from: body)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Upload failed", code: "http")
        }
        let result = try decoder.decode(UploadResult.self, from: respData)
        guard let url = result.url, !url.isEmpty else {
            throw APIError(message: result.error ?? "Upload failed", code: "upload")
        }
        return url
    }

    // MARK: - Typed calls

    func call<T: Decodable>(_ action: String, _ params: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        let data = try await rawData(action, params)
        return try decode(T.self, from: data, action: action)
    }

    // MARK: - Transport

    /// Server-side-AI actions that may take far longer than a normal request.
    static let slowActions: Set<String> = [
        "forum_summary", "home_summary", "thread_summary", "chat_summary",
        "activity_summary", "summary_email_sample",
        "subject_check", "pre_answer", "offtopic_suggest", "offtopic_move",
        "derek_search_start", "derek_search_poll",
    ]

    /// POST the form, validate HTTP + the `{ok:false,error}` envelope, return body Data.
    func rawData(_ action: String, _ params: [String: String]) async throws -> Data {
        var req = URLRequest(url: AppConfig.apiURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        // The app has no subdomain, so it tells the server its chosen language via a header
        // (consumed by dcamp_native_apply_bearer → dcamp_lang). Empty = server default.
        if let lang = UserDefaults.standard.string(forKey: "dcamp_lang"), !lang.isEmpty {
            req.setValue(lang, forHTTPHeaderField: "X-Dcamp-Lang")
        }

        // AI-backed actions generate on the server (summaries, pre-post checks, Derek)
        // and can take 30–60s; the normal 20s timeout would kill them mid-think and
        // leave an empty result (blank summary). Give those the long window.
        req.timeoutInterval = Self.slowActions.contains(action) ? 120 : 20

        var form = params
        form["action"] = action
        form["client"] = AppConfig.nativeClient
        req.httpBody = Self.encodeForm(form)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError(message: "Can’t reach dcamp. \(error.localizedDescription)", code: "network")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "Bad server response", code: "http")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Server error (\(http.statusCode))", code: "http\(http.statusCode)")
        }
        // Envelope check: many actions return {"ok":false,"error":"…"}.
        if let env = try? decoder.decode(Envelope.self, from: data), env.ok == false {
            throw APIError(message: env.error ?? "Request failed", code: "api")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, action: String) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw APIError(message: "Couldn’t read \(action) response.", code: "decode")
                .with(debug: "\(error)\n\(snippet)")
        }
    }

    private static func encodeForm(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let pairs = params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

private extension DcampAPI.APIError {
    func with(debug: String) -> DcampAPI.APIError {
        #if DEBUG
        print("DcampAPI decode debug: \(debug)")
        #endif
        return self
    }
}
