import SwiftUI

/// The player that floats above the tab bar while something plays: the cover
/// dimmed behind glass, and one round button in the middle with the progress
/// drawn around it. A tap anywhere else opens the song.
///
/// It reads each player's own state rather than keeping its own idea of what
/// is playing -- a view that guesses is exactly the bug this app already had.
/// After a pause it stays a moment longer (`MiniPlayerVisibility`).
struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    /// Opens the post the sound belongs to. Nil when there is none -- a song
    /// still being picked in the post sheet -- and the card then offers nothing
    /// to tap, rather than a tap that does nothing.
    let onOpen: (() -> Void)?

    /// Four things in this app can be making sound: a whole song from Apple
    /// Music, Apple's preview and Spotify's embed, all out of this phone, and
    /// the provider over Spotify Connect on whatever device has Spotify open.
    private enum Speaker: Equatable {
        case wholeSong, preview, embed, provider
    }

    /// Whichever is actually running, those on this phone asked first.
    private var playing: Speaker? {
        if wholeSong.song != nil, !wholeSong.isPaused { return .wholeSong }
        if preview.song != nil, !preview.isPaused { return .preview }
        if embed.source != nil, !embed.isPaused { return .embed }
        return store.currentlyPlaying == nil ? nil : .provider
    }

    /// What the card shows: the one playing, or for a moment after a pause the
    /// one that just stopped.
    @State private var shown: Speaker?
    @State private var pausedAt: Date?

    var body: some View {
        SwiftUI.Group {
            if let shown {
                card(shown)
                    // On the card, not around the bar: hidden, the bar must take
                    // no room at all, or the inset would leave an empty strip.
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: shown)
        .onChange(of: shown) { _, now in nowPlaying.isCardShown = now != nil }
        .onChange(of: playing, initial: true) { _, now in
            if let now {
                shown = now
                pausedAt = nil
            } else if shown != nil, pausedAt == nil {
                pausedAt = Date()
            }
        }
        .task(id: pausedAt) {
            guard let pausedAt else { return }
            try? await Task.sleep(for: .seconds(MiniPlayerVisibility.linger))
            // A resume in the meantime cancels this task; so does another pause.
            guard !Task.isCancelled,
                  !MiniPlayerVisibility.isVisible(isPlaying: playing != nil, pausedAt: pausedAt, now: Date())
            else { return }
            shown = nil
            self.pausedAt = nil
        }
    }

    private func card(_ speaker: Speaker) -> some View {
        let isPlaying = playing == speaker
        let time = time(of: speaker)

        return ZStack {
            // Anywhere but the round button opens the song.
            Button { onOpen?() } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            .accessibilityLabel((isPlaying ? "Spielt gerade" : "Pausiert")
                + (time.map { ", \(Spoken.playback(position: $0.position, duration: $0.duration))" } ?? ""))
            .accessibilityHint(onOpen == nil ? "" : "Öffnet den Song")

            playButton(speaker, isPlaying: isPlaying, progress: time.map {
                $0.duration > 0 ? $0.position / $0.duration : 0
            })

            // Quellen-Icons: Apple Music immer, Spotify wenn über Spotify gefunden.
            // Klein und dezent am Rand, nicht im zentralen Bereich um den Play-Button.
            sourceIcons
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background {
            AsyncImage(url: artwork(of: speaker)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.todSurface3
            }
            .opacity(0.35)
            .blur(radius: 16)
            .accessibilityHidden(true)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    /// Apple Music immer sichtbar (die Wiedergabe läuft technisch immer darüber),
    /// Spotify zusätzlich, wenn der Song über einen Spotify-Link/-Suche gefunden wurde.
    private var sourceIcons: some View {
        HStack(spacing: 3) {
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)
                .accessibilityHidden(true)
            if isSpotify {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 0.11, green: 0.71, blue: 0.33))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.3))
        .accessibilityLabel("Wiedergabe über Apple Music"
            + (isSpotify ? ", gefunden über Spotify" : ""))
    }

    /// Ob der aktuell spielende Song über Spotify gefunden wurde.
    private var isSpotify: Bool {
        store.currentlyPlaying?.service == .spotify
    }

    /// The one thing that stands out: bigger than an icon, in the accent colour,
    /// with the progress as a ring around it instead of a bar beside it.
    private func playButton(_ speaker: Speaker, isPlaying: Bool, progress: Double?) -> some View {
        Button { toggle(speaker, isPlaying: isPlaying) } label: {
            ZStack {
                if let progress {
                    Circle().stroke(Color.todLine, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(Color.todAccent2, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Circle().fill(Color.todAccent).padding(6)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.todBackground)
            }
            .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        // Connect can be stopped from here, not started again.
        .disabled(!isPlaying && speaker == .provider)
        .accessibilityLabel(isPlaying ? "Pause" : "Weiterspielen")
    }

    private func toggle(_ speaker: Speaker, isPlaying: Bool) {
        switch speaker {
        case .wholeSong:
            if isPlaying {
                wholeSong.pause()
            } else if let song = wholeSong.song {
                wholeSong.togglePlay(song, from: nil)
            }
        case .preview:
            if isPlaying {
                preview.pause()
            } else if let song = preview.song {
                preview.togglePlay(song)
            }
        case .embed:
            if isPlaying {
                embed.pause()
            } else if let source = embed.source {
                embed.togglePlay(source)
            }
        case .provider:
            Task { await store.stopPlayback() }
        }
    }

    private func artwork(of speaker: Speaker) -> URL? {
        switch speaker {
        case .wholeSong: wholeSong.song?.artworkURL
        case .preview: preview.song?.artworkURL
        case .embed: embed.source?.artworkURL
        case .provider: store.currentlyPlaying?.artworkURL
        }
    }

    /// Position and length, where the speaker reports them. Connect does not.
    private func time(of speaker: Speaker) -> (position: Double, duration: Double)? {
        switch speaker {
        case .wholeSong where wholeSong.duration > 0: (wholeSong.position, wholeSong.duration)
        case .preview where preview.duration > 0: (preview.position, preview.duration)
        case .embed where embed.duration > 0: (embed.position, embed.duration)
        default: nil
        }
    }
}
