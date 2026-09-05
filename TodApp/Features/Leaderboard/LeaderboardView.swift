import SwiftUI

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store

    /// Pure arithmetic over two Ints, so it needs nothing from the main actor.
    /// `View` isolates the whole type, which put this behind `@MainActor` and
    /// left the tests calling it across an isolation boundary; `nonisolated`
    /// lets both the body and a synchronous test call it directly.
    ///
    /// How much of the row's width one entry's bar fills. Guarded on both
    /// ends, because this feeds a SwiftUI frame width and SwiftUI accepts
    /// neither a NaN nor a negative one: a board on which nobody has scored
    /// divides zero by zero, and points go negative as soon as a round of
    /// Aussetzer counts -- which with a negative maximum turned into a bar
    /// several times wider than its row.
    nonisolated static func barFraction(points: Int, max maxPoints: Int) -> Double {
        guard maxPoints > 0 else { return 0 }
        return min(max(Double(points) / Double(maxPoints), 0), 1)
    }

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
                                .frame(width: geo.size.width * Self.barFraction(points: entry.points, max: maxPoints))
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
