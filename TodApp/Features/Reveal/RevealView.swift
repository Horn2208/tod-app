import SwiftUI

struct RevealView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.currentGroup?.submissions ?? []) { submission in
                    HStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: submission.coverColorHex))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text(submission.track).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                            Text(submission.artist).font(.todBody(13)).foregroundStyle(Color.todTextDim)
                        }
                        Spacer()
                        Text(submission.posterID)
                            .font(.todMono(12)).foregroundStyle(Color.todAccent2)
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
        .navigationTitle("Reveal")
    }
}
