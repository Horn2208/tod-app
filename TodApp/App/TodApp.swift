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
                // AppStore loads groups itself once a sign-in attempt lands
                // signed in, so this view only needs to kick the session off.
                await store.restoreSession()
            }
        }
    }
}
