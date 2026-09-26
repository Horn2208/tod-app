import SwiftUI

/// Two tabs, and the profile in the corner.
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
    /// The two pages, left to right: Home, then Gruppen.
    enum Page: Hashable {
        case home
        case gruppen
    }

    @Environment(AppStore.self) private var store
    @Environment(NowPlaying.self) private var nowPlaying
    @State private var isShowingProfile = false
    @State private var selectedPage: Page = .home
    /// The post reopened from the mini player.
    @State private var reopened: Submission?
    /// "Song posten", opened from the "+" in the bar.
    @State private var isPosting = false

    var body: some View {
        // Both pages stay built, so each keeps where it was; only the chosen
        // one shows and takes touches. No system tab bar at all: newer iOS
        // draws its floating one even when told to hide it.
        ZStack {
            page(.home) { TodayView() }
            page(.gruppen) { GroupsFeedView() }
        }
        .tint(.todAccent)
        // Floating over the tab view, at the very bottom -- replaces the
        // system tab bar rather than sitting above it.
        .overlay(alignment: .bottom) {
            RootNavBar(
                selectedPage: selectedPage,
                onSelectPage: { page in withAnimation(.easeOut) { selectedPage = page } },
                post: reopenable,
                onOpenPlayer: reopenable.map { song -> () -> Void in { reopened = song } },
                onPost: { isPosting = true }
            )
        }
        .overlay(alignment: .top) {
            ErrorBanner().padding(.top, 6)
        }
        // What the others post, comment and write in the chosen group
        // arrives while the app is open, on whatever page.
        .task(id: store.currentGroupID) { await store.followGroup() }
        .sheet(item: $reopened) { song in
            SongDetailView(submission: song)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
        .sheet(isPresented: $isPosting) { PostSongView() }
        .sheet(isPresented: $isShowingProfile) {
            // Its own stack: the sheet needs a title bar of its own for the
            // "Fertig" button, and the tab's stack is not underneath it.
            NavigationStack { ProfileView() }
                .presentationBackground(Color.todBackground)
        }
    }

    private func page(_ page: Page, @ViewBuilder content: () -> some View) -> some View {
        let isShown = selectedPage == page
        return NavigationStack {
            content().toolbar { profileButton }
        }
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
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
