import SwiftUI

@main
struct DcampApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var router = Router()
    private let strings = UIStrings.shared
    @State private var summaryPin = SummaryPin()
    @State private var forumFilter = ForumFilterStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .environment(strings)
                .environment(summaryPin)
                .environment(forumFilter)
                .task { await session.start() }
        }
    }
}
