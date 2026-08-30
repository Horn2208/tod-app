import SwiftUI

struct RevealView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: Submission?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.currentGroup?.submissions ?? []) { submission in
                    HStack {
                        AsyncImage(url: submission.source?.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color(hex: submission.coverColorHex))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading) {
                            Text(submission.track).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                            Text(submission.artist).font(.todBody(13)).foregroundStyle(Color.todTextDim)
                        }
                        if submission.source != nil {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Color.todAccent)
                        }
                        Spacer()
                        Text(submission.posterID)
                            .font(.todMono(12)).foregroundStyle(Color.todAccent2)
                    }
                    .padding()
                    .background(Color.todSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture {
                        if submission.source != nil { playing = submission }
                    }
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Reveal")
        .sheet(item: $playing) { submission in
            if let source = submission.source {
                TrackPlayerSheet(
                    candidateTitle: submission.track,
                    artist: submission.artist,
                    source: source
                )
                .presentationDetents([.height(340)])
                .presentationBackground(Color.todBackground)
            }
        }
    }
}
