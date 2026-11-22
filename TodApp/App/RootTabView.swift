import SwiftUI

/// Three tabs (Home, "+", Gruppen), and the profile in the corner.
///
/// The open question in the redesign brief was whether a tab bar is still
/// needed at all. It is, but only for two: Home is what you came for, Gruppen
/// is where everyone else is. Everything group-scoped -- voting, the reveal,
/// the leaderboard, chat, a battle -- now hangs off a group rather than off
/// the app, so those tabs would each have had to answer "for which group?"
/// twice over. The "Mehr" tab held one button; it is gone, and the sign-out
/// it existed for sits in the profile.
///
/// The system tab bar is hidden (`RootNavBar` replaces it): Home left,
/// Gruppen right, the mini player as the glass pill between them, all on one
/// row -- the redesign brief's mini-player layout (17. September).
struct RootTabView: View {
    /// The pages, left to right: Home, the "+" (Song posten), then Gruppen.
    enum Page: Hashable {
        case home
        case post
        case gruppen
    }

    @Environment(AppStore.self) private var store
    @Environment(NowPlaying.self) private var nowPlaying
    @State private var isShowingProfile = false
    @State private var selectedPage: Page = .home
    /// The post reopened from the mini player.
    @State private var reopened: Submission?
    /// A song without a post reopened from the mini player.
    @State private var reopenedItem: NowPlaying.Item?
    /// The big player grows out of the mini player (iOS 18 on).
    @Namespace private var playerZoom
    /// Renews "Song posten" after it closes, so it opens empty next time.
    @State private var postKey = UUID()
    /// Typing in the chat: the bar steps down behind the keyboard, so the
    /// input sits right on it instead of on the bar.
    @State private var isKeyboardUp = false
    /// Notifications are switched off for the app: said at every start, with
    /// the way to switch them on.
    @State private var isPointingToNotificationSettings = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pages showing their first level, nothing pushed onto them. Only
    /// there does a swipe across the content change the page.
    @State private var atRoot: Set<Page> = [.home, .gruppen]
    /// Where each page's sideways rows are, read when a swipe ends -- a box,
    /// not state: the frames move with every scrolled point.
    @State private var sidewaysRows = SidewaysRows()

    var body: some View {
        // Both pages stay built, so each keeps where it was; only the chosen
        // one shows and takes touches. No system tab bar at all: newer iOS
        // draws its floating one even when told to hide it.
        ZStack {
            page(.home) { TodayView() }
            page(.gruppen) { GroupsFeedView() }
            postPage
        }
        // Swiping across the page moves between Home and Gruppen, as on the
        // bar. Beside the scrolling, not instead of it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded { value in
                    let next = RootNavSwipe.page(
                        afterContentSwipe: value.translation.width,
                        dy: value.translation.height,
                        from: selectedPage,
                        isAtRoot: atRoot.contains(selectedPage),
                        beganInSidewaysRow: sidewaysRows.frames[selectedPage, default: []]
                            .contains { $0.contains(value.startLocation) })
                    guard next != selectedPage else { return }
                    withAnimation(Motion.enter) { selectedPage = next }
                }
        )
        .tint(.todAccent)
        .environment(\.isKeyboardUp, isKeyboardUp)
        // Floating over the tab view, at the very bottom -- replaces the
        // system tab bar rather than sitting above it.
        .overlay(alignment: .bottom) {
            RootNavBar(
                selectedPage: selectedPage,
                onSelectPage: { page in withAnimation(Motion.enter) { selectedPage = page } },
                post: reopenable,
                onOpenPlayer: openPlayer,
                onPost: { withAnimation(Motion.enter) { selectedPage = .post } },
                zoom: playerZoom
            )
            .ignoresSafeArea(.keyboard)
            .offset(y: isKeyboardUp ? RootNavBar.height : 0)
            .opacity(isKeyboardUp ? 0 : 1)
            .allowsHitTesting(!isKeyboardUp)
            .animation(.snappy, value: isKeyboardUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardUp = false
        }
        .overlay(alignment: .top) {
            ErrorBanner().padding(.top, 6)
        }
        // What the others post, comment and write in the chosen group
        // arrives while the app is open, on whatever page.
        .task(id: store.currentGroupID) { await store.followGroup() }
        // The round turns over at midnight in Berlin. An app left open then
        // reads the groups again, so today's feed and the reveal move on
        // with the server (the brief's second audit, A3). A few seconds
        // late, so the server's day has surely turned.
        .task {
            while !Task.isCancelled {
                let turn = AppStore.nextRoundTurn(after: Date()).addingTimeInterval(5)
                try? await Task.sleep(for: .seconds(max(1, turn.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                await store.refresh()
                await store.syncReminders()
            }
        }
        // The clock moved by itself: a new day where the phone is, a change
        // of time zone, the clock set by hand.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task {
                await store.refresh()
                await store.syncReminders()
            }
        }
        // At every start: the system's prompt while it is unanswered, a word
        // and the way to the settings once it was answered with no.
        .task {
            if await store.askForRemindersAtStart() == .pointToSettings {
                isPointingToNotificationSettings = true
            }
        }
        .alert("Mitteilungen sind aus", isPresented: $isPointingToNotificationSettings) {
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Später", role: .cancel) {}
        } message: {
            Text("TodApp erinnert dich um 15 Uhr ans Posten und um 20 Uhr ans Voten. Dafür müssen Mitteilungen in den iOS-Einstellungen an sein.")
        }
        .alert(
            "Willkommen",
            isPresented: Binding(
                get: { store.joinedByLink != nil },
                set: { if !$0 { store.joinedByLink = nil } })
        ) {
            Button("Los geht's", role: .cancel) {}
        } message: {
            Text("Du bist jetzt in \(store.joinedByLink ?? "der Gruppe"). Poste deinen Song von heute, dann siehst du, was die anderen hören.")
        }
        .sheet(item: $reopened) { song in
            SongDetailView(submission: song)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
                .playerZoomDestination(in: playerZoom)
        }
        // No post to open: the player alone, for the song as it started.
        .sheet(item: $reopenedItem) { item in
            ScrollView {
                TrackPlayerSheet(
                    candidateTitle: item.title, artist: item.artist, source: item.source,
                    section: item.section, durationSeconds: item.durationSeconds,
                    appleMusicID: item.appleMusicID, isrc: item.isrc,
                    coverColorHex: item.coverColorHex)
            }
            .closesWhenIdle()
            .presentationDetents([.large])
            .presentationBackground(Color.todBackground)
            .playerZoomDestination(in: playerZoom)
        }
        .sheet(isPresented: $isShowingProfile) {
            // Its own stack: the sheet needs a title bar of its own for the
            // "Fertig" button, and the tab's stack is not underneath it.
            NavigationStack { ProfileView() }
                .presentationBackground(Color.todBackground)
        }
        // First sign-in, or an old account still called "Neu": asked once; the
        // saved name closes it.
        .fullScreenCover(isPresented: Binding(
            get: { store.isSignedIn && UserProfile.needsName(store.profile.name) },
            set: { _ in }
        )) {
            NamePromptView()
        }
    }

    private func page(_ page: Page, @ViewBuilder content: () -> some View) -> some View {
        let isShown = selectedPage == page
        return NavigationStack {
            content()
                .toolbar { profileButton }
                // Leaves when a screen is pushed on top, comes back with it.
                .environment(
                    \.isFrontmostPage,
                    isShown && !isShowingProfile && reopened == nil && reopenedItem == nil)
                .onAppear { atRoot.insert(page) }
                .onDisappear { atRoot.remove(page) }
                .onPreferenceChange(SidewaysRowFrames.self) { [sidewaysRows] frames in
                    MainActor.assumeIsolated { sidewaysRows.frames[page] = frames }
                }
        }
        .tabPageDepth(isShown: isShown, reduceMotion: reduceMotion)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
    }

    /// The "+" tab: "Song posten" as a page of its own, back to Home when it
    /// is done or cancelled. Not in `atRoot`: no swipe across it, the song
    /// list and the keyboard want the finger.
    private var postPage: some View {
        let isShown = selectedPage == .post
        return PostSongView {
            postKey = UUID()
            withAnimation(Motion.enter) { selectedPage = .home }
        }
        .id(postKey)
        .tabPageDepth(isShown: isShown, reduceMotion: reduceMotion)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
    }

    /// What a tap on the mini player opens (`MiniPlayerTarget`); nil only
    /// when there is nothing at all, and then the card has nothing to tap.
    private var openPlayer: (() -> Void)? {
        switch MiniPlayerTarget.target(
            submissionID: nowPlaying.submissionID, isLoaded: reopenable != nil,
            hasItem: nowPlaying.item != nil) {
        case .song:
            guard let song = reopenable else { return nil }
            return { reopened = song }
        case .item:
            guard let item = nowPlaying.item else { return nil }
            return { reopenedItem = item }
        case .none:
            return nil
        }
    }

    /// The post the sound belongs to, when the player sheet said which.
    private var reopenable: Submission? {
        guard let id = nowPlaying.submissionID else { return nil }
        return store.groups.flatMap(\.submissions).first { $0.id == id }
    }

    @ToolbarContentBuilder
    private var profileButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { isShowingProfile = true } label: {
                ProfileAvatar(profile: store.profile, size: 30)
            }
            .accessibilityLabel("Profil")
        }
    }
}

@MainActor
private final class SidewaysRows {
    var frames: [RootTabView.Page: [CGRect]] = [:]
}
