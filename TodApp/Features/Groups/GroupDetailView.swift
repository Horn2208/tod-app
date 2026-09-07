import SwiftUI

/// Everything that belongs to one group. Voting, Reveal, the leaderboard, the
/// chat and battles all read `AppStore.currentGroup`, which is why the app used
/// to carry a group switcher on every screen. Once a group is a place you go
/// to, "which group" follows from where you are.
struct GroupDetailView: View {
    @Environment(AppStore.self) private var store
    let group: Group

    var body: some View {
        List {
            NavigationLink("Voten") { VotingView() }
            NavigationLink("Reveal") { RevealView() }
            NavigationLink("Rangliste") { LeaderboardView() }
            NavigationLink("Chat") { ChatView() }
            NavigationLink("Battle") { BattleView() }
        }
        .listStyle(.plain)
        .font(.todBody(16))
        .foregroundStyle(Color.todText)
        .scrollContentBackground(.hidden)
        .background(Color.todBackground)
        .navigationTitle(group.name)
        .onAppear { store.selectGroup(group.id) }
    }
}
