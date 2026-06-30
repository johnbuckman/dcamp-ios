import SwiftUI

/// SwiftUI entry point that hosts the UIKit web container full-screen.
struct RootView: View {
    var body: some View {
        WebContainer()
            .ignoresSafeArea()
    }
}

/// Bridges the UIKit WebViewController into SwiftUI.
struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}
