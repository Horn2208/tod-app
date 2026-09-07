import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            NavigationStack { VotingView() }
                .tabItem { Label("Voten", systemImage: "hand.thumbsup.fill") }

            NavigationStack { RevealView() }
                .tabItem { Label("Reveal", systemImage: "sparkles") }

            NavigationStack { LeaderboardView() }
                .tabItem { Label("Rangliste", systemImage: "trophy.fill") }

            NavigationStack { ChatView() }
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack { BattleView() }
                .tabItem { Label("Battle", systemImage: "bolt.fill") }

            NavigationStack { MoreView() }
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }
        }
        .tint(.todAccent)
        .safeAreaInset(edge: .top) {
            GroupSwitcher()
        }
    }
}

private struct GroupSwitcher: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.groups) { group in
                    Button {
                        store.selectGroup(group.id)
                    } label: {
                        Label(group.name, systemImage: "circle.fill")
                            .labelStyle(.titleOnly)
                            .font(.todMono(13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(group.id == store.currentGroupID ? Color.todAccent : Color.todSurface2)
                            .foregroundStyle(group.id == store.currentGroupID ? .white : Color.todTextDim)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }
}
