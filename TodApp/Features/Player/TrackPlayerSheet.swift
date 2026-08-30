import SwiftUI

struct TrackPlayerSheet: View {
    let candidateTitle: String
    let artist: String
    let source: TrackSource

    @Environment(\.dismiss) private var dismiss

    private var embedHeight: CGFloat {
        // Spotify's compact player is shorter than SoundCloud's widget.
        source.service == .spotify ? 152 : 166
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidateTitle)
                    .font(.todDisplay(20))
                    .foregroundStyle(Color.todText)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todTextDim)
                }
            }

            TrackEmbedView(source: source)
                .frame(height: embedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Link(destination: source.pageURL) {
                Text(source.service == .spotify ? "In Spotify öffnen" : "In SoundCloud öffnen")
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todBackground)
        .presentationDetents([.height(340)])
        .presentationBackground(Color.todBackground)
    }
}
