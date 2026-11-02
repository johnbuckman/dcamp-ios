#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacUpdateSettingsSection: View {
    private let updater = MacUpdater.shared

    var body: some View {
        Section {
            Toggle(T("Check automatically"), isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            ))
            .disabled(!updater.isAvailable)
            Button(T("Check for Updates…")) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        } header: {
            Text(T("App updates"))
        } footer: {
            if updater.isAvailable {
                Text(T("Checks at startup and once a day while dcamp is open."))
            } else {
                Text(T("Automatic updates are unavailable in this build."))
                Link(T("Download the latest version"), destination: URL(string: "https://github.com/johnbuckman/dcamp-ios/releases/latest")!)
            }
        }
    }
}
#endif
