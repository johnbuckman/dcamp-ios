import SwiftUI

@main
struct DcampApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var router = Router()
    @State private var strings = UIStrings()
    @State private var summaryPin = SummaryPin()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .environment(strings)
                .environment(summaryPin)
                .task { await session.start() }
        }
    }
}
