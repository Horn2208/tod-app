import SwiftUI

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let board = store.currentGroup?.board ?? []
        let maxPoints = board.map(\.points).max() ?? 1

        ScrollView {
            VStack(spacing: 10) {
                ForEach(board) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.name).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                            Spacer()
                            Text("\(entry.points) pts").font(.todMono(13, weight: .semibold)).foregroundStyle(Color.todAccent2)
                        }
                        Text(entry.subtitle).font(.todBody(12)).foregroundStyle(Color.todTextDim)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.todAccent)
                                .frame(width: geo.size.width * (Double(entry.points) / Double(maxPoints)))
                        }
                        .frame(height: 6)
                        .background(Color.todSurface3)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding()
                    .background(Color.todSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Rangliste")
    }
}
