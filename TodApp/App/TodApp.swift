import SwiftUI

@main
struct TodApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                // The design tokens are fixed dark hex values, so system-provided
                // chrome (nav titles, `.bar` materials, tab bar) must resolve dark too.
                .preferredColorScheme(.dark)
                .task { await store.loadGroups() }
        }
    }
}
