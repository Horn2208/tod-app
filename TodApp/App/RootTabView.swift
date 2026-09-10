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
    @State private var isShowingProfile = false

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
        .safeAreaInset(edge: .bottom) {
            MiniPlayerBar(onOpen: {})
        }
        .sheet(isPresented: $isShowingProfile) {
            // Its own stack: the sheet needs a title bar of its own for the
            // "Fertig" button, and the tab's stack is not underneath it.
            NavigationStack { ProfileView() }
                .presentationBackground(Color.todBackground)
        }
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
