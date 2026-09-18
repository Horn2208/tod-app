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
struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(NowPlaying.self) private var nowPlaying
    @State private var isShowingProfile = false
    /// The post reopened from the mini player.
    @State private var reopened: Submission?

    var body: some View {
        TabView {
            NavigationStack {
                TodayView().toolbar { profileButton }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                GroupsFeedView().toolbar { profileButton }
            }
            .tabItem { Label("Gruppen", systemImage: "person.2.fill") }
        }
        .tint(.todAccent)
        // Floating over the tab view, above the tab bar. Screens with something
        // at their bottom make room for it themselves (`leavesRoomForMiniPlayer`).
        .overlay(alignment: .bottom) {
            miniPlayer.padding(.bottom, 49)
        }
        .overlay(alignment: .top) {
            ErrorBanner().padding(.top, 6)
        }
        .sheet(item: $reopened) { song in
            SongDetailView(submission: song)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
        .sheet(isPresented: $isShowingProfile) {
            // Its own stack: the sheet needs a title bar of its own for the
            // "Fertig" button, and the tab's stack is not underneath it.
            NavigationStack { ProfileView() }
                .presentationBackground(Color.todBackground)
        }
    }

    /// The mini player, laid over the tab view as the brief asks. Laid over on
    /// its own it hid the bottom of whatever was underneath -- the feed's
    /// "0 von 4 bewertet" among it -- and a safe-area inset on each tab's stack
    /// did not reach the screens pushed onto it. So the card floats, and the
    /// screens make room for it (`leavesRoomForMiniPlayer`).
    private var miniPlayer: some View {
        MiniPlayerBar(post: reopenable, onOpen: reopenable.map { song -> () -> Void in { reopened = song } })
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
