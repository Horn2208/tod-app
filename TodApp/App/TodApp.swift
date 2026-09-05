import SwiftUI

@main
struct TodApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                if store.isSignedIn {
                    RootTabView()
                } else {
                    SignInView()
                }
            }
            .environment(store)
            // The design tokens are fixed dark hex values, so system-provided
            // chrome (nav titles, `.bar` materials, tab bar) must resolve dark too.
            .preferredColorScheme(.dark)
            .task {
                await store.restoreSession()
                if store.isSignedIn { await store.loadGroups() }
            }
        }
    }
}
