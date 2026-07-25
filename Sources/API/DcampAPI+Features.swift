import Foundation

// Additional API actions for the full dcamp feature set (summaries, settings,
// reactions, edit/delete, message status, DM participants, people actions).
// These use the non-private `call`/`rawData` on the actor.
extension DcampAPI {

    // MARK: - Summaries

    func homeSummaryInfo() async -> SummaryInfo { (try? await call("home_summary_info")) ?? SummaryInfo() }

    func homeSummary(days: Int) async throws -> SummaryResult {
        try await call("home_summary", ["days": String(days)])
    }
    func forumSummary(projectID: Int, days: Int) async throws -> SummaryResult {
        try await call("forum_summary", ["project_id": String(projectID), "days": String(days)])
    }
    func threadSummary(messageID: Int, days: Int) async throws -> SummaryResult {
        try await call("thread_summary", ["id": String(messageID), "days": String(days)])
    }
    func chatSummary(days: Int, room: String = "main") async throws -> SummaryResult {
        try await call("chat_summary", ["days": String(days), "room": room])
    }
    /// Multi-source digest used by the Summaries-by-email page.
    func activitySummary(sources: String, period: String) async -> SummaryResult {
        (try? await call("activity_summary", ["sources": sources, "period": period])) ?? SummaryResult()
    }
    func summaryEmailSample(sources: String, period: String) async {
        _ = try? await rawData("summary_email_sample", ["sources": sources, "period": period])
    }

    // MARK: - AI pipeline (pre-post checks + Ask-Derek)

    func subjectCheck(subject: String, body: String) async -> SubjectCheck {
        (try? await call("subject_check", ["subject": subject, "body": body])) ?? SubjectCheck(verdict: "good")
    }
    func preAnswer(subject: String, body: String) async -> PreAnswer {
        (try? await call("pre_answer", ["subject": subject, "body": body])) ?? PreAnswer()
    }
    func offtopicSuggest(commentID: Int) async -> OfftopicSuggest {
        (try? await call("offtopic_suggest", ["id": String(commentID)])) ?? OfftopicSuggest()
    }
    func offtopicMove(commentID: Int) async -> CreateResult {
        let r: CreateResult? = try? await call("offtopic_move", ["id": String(commentID)])
        return r ?? CreateResult()
    }
    func derekSearchStart(_ query: String) async -> DerekStart {
        (try? await call("derek_search_start", ["q": query])) ?? DerekStart()
    }
    func derekSearchPoll(token: String) async -> DerekPoll {
        (try? await call("derek_search_poll", ["token": token])) ?? DerekPoll()
    }

    // MARK: - Streaming helpers

    /// Re-fetch a single comment (used to grow a streaming @derek/@deepseek reply).
    func commentOne(id: Int) async -> Comment? {
        struct R: Codable { var comment: Comment? }
        let r: R? = try? await call("comment_one", ["id": String(id)])
        return r?.comment
    }

    // MARK: - Account

    func emailChange(_ email: String) async -> Envelope {
        let r: Envelope? = try? await call("email_change", ["email": email])
        return r ?? Envelope()
    }
    func bcUnlink() async { _ = try? await rawData("bc_unlink", [:]) }

    // MARK: - Settings / account

    func summaryPrefsGet() async -> SummaryPrefs { (try? await call("summary_prefs_get")) ?? SummaryPrefs() }
    func summaryPrefsSave(sources: String, period: String, emailEnabled: Bool) async {
        _ = try? await rawData("summary_prefs_save", ["sources": sources, "period": period, "email_enabled": emailEnabled ? "1" : "0"])
    }
    func locationGet() async -> LocationInfo { (try? await call("location_get")) ?? LocationInfo() }
    func locationSave(country: String, city: String) async {
        _ = try? await rawData("location_save", ["country": country, "city": city])
    }
    /// avatarImg must be the member's CURRENT avatar URL — the server treats
    /// avatar_img as an overwrite (the web sends ME.avatar_img), so passing "" here
    /// blanked the avatar on every profile save.
    func settingsSave(name: String, about: String, avatarImg: String, showLocation: Bool) async {
        _ = try? await rawData("settings_save", ["name": name, "avatar_img": avatarImg, "about": about, "show_location": showLocation ? "1" : "0"])
    }
    func accountClose() async { _ = try? await rawData("account_close", [:]) }
    func uiPrefsSave(name: String, value: String) async {
        _ = try? await rawData("ui_prefs_save", ["name": name, "value": value])
    }

    // MARK: - Muted people

    func personMutes() async -> [Person] {
        struct R: Codable { var people: [Person]?; var mutes: [Person]? }
        let r: R? = try? await call("person_mutes")
        return r?.people ?? r?.mutes ?? []
    }
    func personMute(id: Int) async { _ = try? await rawData("person_mute", ["id": String(id)]) }
    func personUnmute(id: Int) async { _ = try? await rawData("person_unmute", ["id": String(id)]) }
    func reportPerson(id: Int, reason: String, url: String) async {
        _ = try? await rawData("report_person", ["id": String(id), "reason": reason, "url": url])
    }

    // MARK: - Reactions

    func boostToggle(type: String, id: Int, content: String) async {
        _ = try? await rawData("boost_toggle", ["type": type, "id": String(id), "content": content])
    }

    // MARK: - Edit / delete / status

    func messageUpdate(id: Int, categoryID: Int, subject: String, bodyHTML: String) async throws {
        _ = try await rawData("message_update", ["id": String(id), "category_id": String(categoryID), "subject": subject, "body": bodyHTML])
    }
    func messageSetStatus(id: Int, status: String) async {
        _ = try? await rawData("message_set_status", ["id": String(id), "status": status])
    }
    func messageStatus(id: Int, status: String) async {   // status=deleted to soft-delete
        _ = try? await rawData("message_status", ["id": String(id), "status": status])
    }
    func messagePin(id: Int, pinned: Bool) async {
        _ = try? await rawData("message_pin", ["id": String(id), "pinned": pinned ? "1" : "0"])
    }
    func commentUpdate(id: Int, bodyHTML: String) async throws {
        _ = try await rawData("comment_update", ["id": String(id), "body": bodyHTML])
    }
    func commentDelete(id: Int) async { _ = try? await rawData("comment_delete", ["id": String(id)]) }
    func chatUpdate(id: Int, bodyHTML: String) async throws {
        _ = try await rawData("chat_update", ["id": String(id), "body": bodyHTML])
    }
    func chatDelete(id: Int) async { _ = try? await rawData("chat_delete", ["id": String(id)]) }

    // MARK: - DM participants

    func dmArchive(convoID: Int) async { _ = try? await rawData("dm_archive", ["convo": String(convoID)]) }
    func dmRemove(convoID: Int, personID: Int) async {
        _ = try? await rawData("dm_remove", ["convo": String(convoID), "person": String(personID)])
    }
    func dmInvite(convoID: Int, participantIDs: [Int], days: Int) async {
        _ = try? await rawData("dm_invite", ["convo": String(convoID),
                                             "participants": participantIDs.map(String.init).joined(separator: ","),
                                             "days": String(days)])
    }
    func dmDirect(personID: Int) async throws -> Int {
        struct R: Codable { var id: Int?; var convo: Int?; var error: String? }
        let r: R = try await call("dm_direct", ["person": String(personID)])
        guard let id = r.id ?? r.convo else { throw APIError(message: r.error ?? "Couldn’t open conversation", code: nil) }
        return id
    }

    // MARK: - People

    // MARK: - Forum discovery

    func projectsDiscover(kind: String) async -> [Board] {
        struct R: Codable { var projects: [Board] = [] }
        let r: R? = try? await call("projects_discover", ["kind": kind])
        return r?.projects ?? []
    }
    func projectJoin(id: Int) async { _ = try? await rawData("project_join", ["id": String(id)]) }
    func projectLeave(id: Int) async { _ = try? await rawData("project_leave", ["id": String(id)]) }

    func personActivity(id: Int) async -> [CardMessage] {
        struct R: Codable { var items: [CardMessage]?; var activity: [CardMessage]? }
        let r: R? = try? await call("person_activity", ["id": String(id)])
        return r?.items ?? r?.activity ?? []
    }
}
