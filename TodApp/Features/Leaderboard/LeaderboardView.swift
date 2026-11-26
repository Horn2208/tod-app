import SwiftUI

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store

    /// A thin metallic sheen instead of a flat fill. Kept to two places in the
    /// whole app -- the top of this table and the streak on Home -- because it
    /// stops reading as special the moment everything wears it.
    static let goldSheen = LinearGradient(
        colors: [Color.todAccent2, Color(hex: "#fff2cc")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
        let totals = store.seasonTotals
        let maxPoints = totals.map(\.points).max() ?? 1

        ScrollView {
            VStack(spacing: 10) {
                if totals.allSatisfy({ $0.roundsPlayed == 0 }) {
                    nothingYet
                }
                ForEach(Array(totals.enumerated()), id: \.element.id) { index, entry in
                    // Only a real lead is crowned. On an all-zero table nobody
                    // is ahead, and whoever the sort happened to put first must
                    // not be dressed up as the winner.
                    row(entry, isLeader: index == 0 && entry.points > 0, max: maxPoints)
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity)
            .padding()
        }
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle("Rangliste")
        .task(id: store.currentGroupID) { await store.loadSeasonTotals() }
    }

    private var nothingYet: some View {
        Text("Noch keine aufgedeckte Runde. Die Punkte von heute zählen ab morgen mit.")
            .font(.todBody(13))
            .foregroundStyle(Color.todTextDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.todSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ entry: SeasonTotal, isLeader: Bool, max maxPoints: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.goldSheen)
                        // The lead is in the row's label; a second "Krone"
                        // in front of it would only be furniture.
                        .accessibilityHidden(true)
                }
                Text(entry.name)
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text("\(entry.points) pts")
                    .font(.todMono(13, weight: .semibold))
                    .foregroundStyle(
                        isLeader ? AnyShapeStyle(Self.goldSheen) : AnyShapeStyle(Color.todAccent2)
                    )
            }

            Text(subtitle(entry))
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)

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
        // One row, one sentence -- otherwise a name, a number, a subtitle and
        // a bar arrive as four separate stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Spoken.leaderboardRow(
            name: entry.name, points: entry.points,
            subtitle: subtitle(entry), isLeader: isLeader))
    }

    /// Zero from six rounds is not zero from none, and the table is the one
    /// place that can say which it is.
    private func subtitle(_ entry: SeasonTotal) -> String {
        switch entry.roundsPlayed {
        case 0: "Noch keine Runde gespielt"
        case 1: "1 aufgedeckte Runde"
        case let count: "\(count) aufgedeckte Runden"
        }
    }
}
