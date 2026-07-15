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

    // MARK: - Settings / account

    func summaryPrefsGet() async -> SummaryPrefs { (try? await call("summary_prefs_get")) ?? SummaryPrefs() }
    func summaryPrefsSave(sources: String, period: String, emailEnabled: Bool) async {
        _ = try? await rawData("summary_prefs_save", ["sources": sources, "period": period, "email_enabled": emailEnabled ? "1" : "0"])
    }
    func locationGet() async -> LocationInfo { (try? await call("location_get")) ?? LocationInfo() }
    func locationSave(country: String, city: String) async {
        _ = try? await rawData("location_save", ["country": country, "city": city])
    }
    func settingsSave(name: String, about: String, showLocation: Bool) async {
        _ = try? await rawData("settings_save", ["name": name, "avatar_img": "", "about": about, "show_location": showLocation ? "1" : "0"])
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
