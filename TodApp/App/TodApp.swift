import SwiftUI

@main
struct TodApp: App {
#if DEBUG
    /// Skips the sign-in gate when the app is launched with `-skipSignIn`.
    /// Debug-only and opt-in: it exists so screens can be looked at without a
    /// Spotify account, not as a way around the gate. Nothing else is faked --
    /// with no session there is no token, so search and playback still fail.
    private var skipsSignIn: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipSignIn")
    }
#else
    private var skipsSignIn: Bool { false }
#endif

    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    /// The only one in the app. Made here so it outlives every sheet: a player
    /// built inside one stops playing the moment that sheet closes.
    @State private var embedPlayer = SpotifyEmbedPlayer()

    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                if store.isRestoringSession {
                    // Neither screen is correct yet -- a launch that will end up
                    // signed in must not flash SignInView first, and one that
                    // won't must not flash the tab bar. Stay neutral until
                    // restoreSession() has settled it either way.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.todBackground)
                } else if store.isSignedIn || skipsSignIn {
                    RootTabView()
                } else {
                    SignInView()
                }
            }
            .environment(store)
            .environment(embedPlayer)
            // The player's web view has to be in the hierarchy to keep
            // running, and has no business being seen. Zero size, at the root,
            // underneath everything.
            .background(alignment: .bottom) {
                EmbedHostView(player: embedPlayer)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            // The design tokens are fixed dark hex values, so system-provided
            // chrome (nav titles, `.bar` materials, tab bar) must resolve dark too.
            .preferredColorScheme(.dark)
            .task {
                // AppStore loads groups itself once a sign-in attempt lands
                // signed in, so this view only needs to kick the session off.
                await store.restoreSession()
                // The debug bypass skips the sign-in that would have loaded
                // them, so without this the tab bar appears over an app with
                // nothing in it.
                if skipsSignIn && !store.isSignedIn { await store.loadGroups() }
            }
            // Back in front can mean a new day: today's reminders are decided
            // against the groups as they are now, not as they were yesterday.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.syncReminders() } }
            }
        }
    }
}
