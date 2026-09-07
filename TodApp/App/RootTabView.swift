import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                List(store.groups) { group in
                    NavigationLink(group.name) { GroupDetailView(group: group) }
                }
                .listStyle(.plain)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .scrollContentBackground(.hidden)
                .background(Color.todBackground)
                .navigationTitle("Gruppen")
            }
            .tabItem { Label("Gruppen", systemImage: "person.2.fill") }

            // Stays until Plan 2's profile screen takes over the sign-out that
            // lives here. Removing it now would strand the only way out of a
            // Spotify session.
            NavigationStack { MoreView() }
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
        }
        .tint(.todAccent)
        .safeAreaInset(edge: .bottom) {
            MiniPlayerBar(onOpen: {})
        }
    }
}
