import SwiftUI

/// A thin bar that appears only while something is playing. Tapping it opens
/// the full song view; the button stops playback. It reads each player's own
/// state rather than keeping its own idea of what is playing -- a view that
/// guesses is exactly the bug this app already had.
struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(PreviewPlayer.self) private var preview
    let onOpen: () -> Void

    /// Three things in this app can be making sound: Apple's preview and
    /// Spotify's embed, both out of this phone, and the provider over Spotify
    /// Connect on whatever device has Spotify open. The bar belongs to
    /// whichever is actually running, the two on this phone asked first.
    private enum Speaker {
        case preview, embed
        case provider(TrackSource)
    }

    private var speaker: Speaker? {
        if preview.song != nil, !preview.isPaused { return .preview }
        if embed.source != nil, !embed.isPaused { return .embed }
        return store.currentlyPlaying.map(Speaker.provider)
    }

    private var artwork: URL? {
        switch speaker {
        case .preview: preview.song?.artworkURL
        case .embed: embed.source?.artworkURL
        case .provider(let source): source.artworkURL
        case nil: nil
        }
    }

    /// Position and length, where the speaker reports them. Connect does not.
    private var time: (position: Double, duration: Double)? {
        switch speaker {
        case .preview where preview.duration > 0: (preview.position, preview.duration)
        case .embed where embed.duration > 0: (embed.position, embed.duration)
        default: nil
        }
    }

    var body: some View {
        if let speaker {
            HStack(spacing: 12) {
                // A button, not a tap gesture on the whole bar: opening the
                // song has to be something VoiceOver can find and press, and
                // it must not swallow the pause button beside it.
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        AsyncImage(url: artwork) { image in
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
                            if let time {
                                Text("\(TrackPlayerSheet.timestamp(time.position)) / \(TrackPlayerSheet.timestamp(time.duration))")
                                    .font(.todMono(10))
                                    .foregroundStyle(Color.todTextFaint)
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Spielt gerade" + (time.map { ", \(Spoken.playback(position: $0.position, duration: $0.duration))" } ?? ""))
                .accessibilityHint("Öffnet den Song")

                Button {
                    // Pauses whatever this bar is currently speaking for.
                    switch speaker {
                    case .preview: preview.pause()
                    case .embed: embed.pause()
                    case .provider: Task { await store.stopPlayback() }
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
        }
    }
}
