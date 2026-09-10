import SwiftUI

/// A thin bar that appears only while something is playing. Tapping it opens
/// the full song view; the button stops playback. It reads the store's mirror
/// of the provider's playback state rather than keeping its own idea of what
/// is playing -- a view that guesses is exactly the bug this app already had.
struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyEmbedPlayer.self) private var embed
    let onOpen: () -> Void

    /// Two things in this app can be making sound: the provider, playing
    /// through Spotify Connect on whatever device has Spotify open, and this
    /// app's own embed player. The bar belongs to whichever is actually
    /// running -- and the embed is asked first, because it is the one playing
    /// out of this phone.
    private var embedIsPlaying: Bool { embed.source != nil && !embed.isPaused }

    private var playing: TrackSource? {
        embedIsPlaying ? embed.source : store.currentlyPlaying
    }

    var body: some View {
        if let playing {
            HStack(spacing: 12) {
                AsyncImage(url: playing.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.todSurface3)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Spielt gerade")
                        .font(.todBody(13))
                        .foregroundStyle(Color.todTextDim)
                    if embedIsPlaying, embed.duration > 0 {
                        Text("\(TrackPlayerSheet.timestamp(embed.position)) / \(TrackPlayerSheet.timestamp(embed.duration))")
                            .font(.todMono(10))
                            .foregroundStyle(Color.todTextFaint)
                    }
                }

                Spacer()

                Button {
                    // Pauses whatever this bar is currently speaking for.
                    if embedIsPlaying {
                        embed.pause()
                    } else {
                        Task { await store.stopPlayback() }
                    }
                } label: {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Color.todText)
                        .padding(8)
                }
                .accessibilityLabel("Wiedergabe pausieren")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.todLine).frame(height: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }
}
