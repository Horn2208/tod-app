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
        // NOT `.presentationDetents`/`.presentationBackground` here: those
        // target "the enclosing sheet" (per SwiftUI's own docs) regardless of
        // how deep this view sits in the hierarchy. PostSongView embeds this
        // view INLINE inside its own already-presented sheet, and those two
        // modifiers would hijack and forcibly resize/collapse THAT sheet the
        // instant a candidate is selected. Apply them at the call site that
        // actually presents this view as a sheet (RevealView) instead.
    }
}
