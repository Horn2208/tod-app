import SwiftUI

@main
struct TodApp: App {
#if DEBUG
    /// Skips the sign-in gate when the app is launched with `-skipSignIn`.
    /// Debug-only and opt-in: it exists so screens can be looked at without an
    /// account, not as a way around the gate. Nothing else is faked -- with no
    /// session the server answers nothing.
    private var skipsSignIn: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipSignIn")
    }
#else
    private var skipsSignIn: Bool { false }
#endif

    /// The store on the build's backend. A debug build launched with
    /// `-inMemoryData` stays on the demo data instead, so screens can be looked
    /// at without a network or an account.
    private static func makeStore() -> AppStore {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-inMemoryData") {
            return AppStore(accountService: LocalAccountService())
        }
#endif
        return AppStore.live()
    }

    @State private var store = TodApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase
    /// The only one in the app. Made here so it outlives every sheet: a player
    /// built inside one stops playing the moment that sheet closes.
    @State private var embedPlayer = SpotifyEmbedPlayer()
    /// SoundCloud's widget, hidden and steered the same way.
    @State private var soundCloudPlayer = SoundCloudEmbedPlayer()
    /// Native previews from the catalog, and the matching that finds them.
    /// App-wide for the same reason as the embed: one voice at a time, and a
    /// song looked up once.
    @State private var previewPlayer = PreviewPlayer()
    @State private var catalogResolver = CatalogResolver.appleMusicFirst()
    /// Whether Apple Music is allowed and plays whole songs, and the player
    /// that plays them. App-wide like the others: the profile connects, the
    /// player sheet chooses, the mini player reports.
    @State private var appleMusicAccess = AppleMusicAccess()
    @State private var appleMusicPlayer = AppleMusicPlayer()
    /// Which post the sound belongs to, so the mini player can open it again.
    @State private var nowPlaying = NowPlaying()
    /// Spotify's App Remote: the whole song in the Spotify app, and back.
    @State private var spotifyRemote = SpotifyRemote(
        clientID: Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? "")

    init() {
        SupabaseConfig.reportOnLaunch()
    }

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
            .environment(previewPlayer)
            .environment(spotifyRemote)
            // An invite link first; anything else is the Spotify app
            // handing back after starting a song.
            .onOpenURL { url in
                if store.openInvite(url) { return }
                spotifyRemote.handle(url)
            }
            .environment(catalogResolver)
            .environment(appleMusicAccess)
            .environment(appleMusicPlayer)
            .environment(nowPlaying)
            .environment(soundCloudPlayer)
            // The player's web view has to be in the hierarchy to keep
            // running, and has no business being seen. Zero size, at the root,
            // underneath everything.
            .background(alignment: .bottom) {
                ZStack {
                    EmbedHostView(webView: embedPlayer.webView)
                    EmbedHostView(webView: soundCloudPlayer.webView)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            // The design tokens are fixed dark hex values, so system-provided
            // chrome (nav titles, `.bar` materials, tab bar) must resolve dark too.
            .preferredColorScheme(.dark)
            .task {
                // AppStore loads groups itself once an account is signed in,
                // so this view only needs to kick the session off.
                await store.restoreSession()
                // The debug bypass skips the sign-in that would have loaded
                // them, so without this the tab bar appears over an app with
                // nothing in it.
                if skipsSignIn && !store.isSignedIn { await store.loadGroups() }
#if DEBUG
                // Straight past the start screen, for looking at the app in the
                // simulator: the same as tapping "Ohne Anmeldung weiter".
                if ProcessInfo.processInfo.arguments.contains("-anonymousSignIn") && !store.isSignedIn {
                    await store.continueWithoutAccount()
                }
#endif
            }
            // A subscription can start or end while the app runs. The player
            // picks whole songs, or stops picking them, without a restart.
            .task { await appleMusicAccess.followSubscription() }
            // On disconnecting, the sign-in page's Spotify session is cleared,
            // or the next connection would quietly reuse the old account.
            .onChange(of: store.isSpotifyConnected) { _, connected in
                guard !connected else { return }
                Task { await WebAuthentication.forgetSpotifyLogin() }
            }
            // Back in front can mean a new day: today's reminders are decided
            // against the groups as they are now, not as they were yesterday.
            .onChange(of: scenePhase) { _, phase in
                // It can also mean back from Settings, where Apple Music may
                // just have been switched on or off for this app.
                // And it can mean others posted, voted or wrote meanwhile.
                if phase == .background {
                    spotifyRemote.disconnect()
                }
                if phase == .active {
                    spotifyRemote.reconnectIfNeeded()
                    Task {
                        await store.refresh()
                        await store.syncReminders()
                        await appleMusicAccess.refresh()
                    }
                }
            }
        }
    }
}
