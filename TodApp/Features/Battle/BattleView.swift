import SwiftUI

struct BattleView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            if let battle = store.currentGroup?.activeBattle {
                VStack(spacing: 16) {
                    Text(battle.mode.rawValue)
                        .font(.todDisplay(18))
                        .foregroundStyle(Color.todAccent2)

                    HStack(spacing: 12) {
                        BattleEntryCard(entry: battle.player1)
                        Text("VS").font(.todMono(13, weight: .bold)).foregroundStyle(Color.todTextFaint)
                        BattleEntryCard(entry: battle.player2)
                    }

                    if !battle.diceArtists.isEmpty {
                        Text(battle.diceArtists.joined(separator: " · "))
                            .font(.todMono(11))
                            .foregroundStyle(Color.todTextDim)
                    }
                }
                // Claim the full width explicitly; do not rely on a child
                // (button, spacer) happening to stretch the container.
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Kein aktives Battle")
                        .font(.todBody(15))
                        .foregroundStyle(Color.todTextDim)
                    Button("Battle starten") {}
                        .buttonStyle(TodPrimaryButtonStyle())
                }
                // Claim the full width explicitly; do not rely on a child
                // (button, spacer) happening to stretch the container.
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .background(Color.todBackground)
        .navigationTitle("Battle")
    }
}

private struct BattleEntryCard: View {
    let entry: BattleEntry

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: entry.source?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(hex: entry.coverColorHex))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(entry.name).font(.todBody(13, weight: .bold)).foregroundStyle(Color.todText)
            Text("\(entry.percentage)%").font(.todMono(12, weight: .semibold)).foregroundStyle(Color.todGood)
        }
    }
}
