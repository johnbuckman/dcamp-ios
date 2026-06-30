import SwiftUI

@main
struct DcampApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .ignoresSafeArea(.keyboard)   // let the web view manage the keyboard inset
        }
    }
}
