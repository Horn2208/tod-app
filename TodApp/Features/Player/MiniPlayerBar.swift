import SwiftUI

/// The player that floats above the tab bar while something plays: the cover
/// on the left, title and artist beside it, and the round play button on the
/// right with the progress drawn around it. A tap anywhere but the button
/// opens the song.
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
    /// The post the sound belongs to, when there is one. It names the song the
    /// way the group saw it, and the Spotify mark follows how it was found.
    let post: Submission?
    /// Opens that post. Nil when there is none -- a song still being picked in
    /// the post sheet -- and the card then offers nothing to tap, rather than a
    /// tap that does nothing.
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
        let names = names(of: speaker)

        return HStack(spacing: 12) {
            openable(
                HStack(spacing: 12) {
                    cover(speaker)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(names.track)
                            .font(.todBody(14, weight: .bold))
                            .foregroundStyle(Color.todText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !names.artist.isEmpty {
                                Text(names.artist)
                                    .font(.todBody(12))
                                    .foregroundStyle(Color.todTextDim)
                                    .lineLimit(1)
                            }
                            sourceIcons(speaker)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Spoken.song(track: names.track, artist: names.artist)
                    + (isPlaying ? ", spielt gerade" : ", pausiert")
                    + (time.map { ", \(Spoken.playback(position: $0.position, duration: $0.duration))" } ?? ""))
            )

            playButton(speaker, isPlaying: isPlaying, progress: time.map {
                $0.duration > 0 ? $0.position / $0.duration : 0
            })
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
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

    /// A button where there is a post to open, the bare content where there is
    /// not -- a disabled button would dim the title for no reason.
    @ViewBuilder
    private func openable(_ content: some View) -> some View {
        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet den Song")
        } else {
            content
        }
    }

    private func cover(_ speaker: Speaker) -> some View {
        AsyncImage(url: artwork(of: speaker)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            post.map { Color(hex: $0.coverColorHex) } ?? Color.todSurface3
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.todLine, lineWidth: 0.5))
    }

    /// Which service is making the sound, small beside the artist. Apple's mark
    /// for a whole song or a preview, Spotify's for the embed and Connect, and
    /// Spotify's too for a post that was found through Spotify.
    private func sourceIcons(_ speaker: Speaker) -> some View {
        let viaApple = speaker == .wholeSong || speaker == .preview
        let viaSpotify = speaker == .embed || speaker == .provider
            || SourceAttribution.foundViaSpotify(post)
        return HStack(spacing: 3) {
            if viaApple {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
            }
            if viaSpotify {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 0.11, green: 0.71, blue: 0.33))
            }
        }
        .accessibilityHidden(true)
    }

    /// The post's names where there is a post; otherwise what the catalog
    /// calls the song. Connect reports neither.
    private func names(of speaker: Speaker) -> (track: String, artist: String) {
        if let post { return (post.track, post.artist) }
        let song: CatalogSong? = switch speaker {
        case .wholeSong: wholeSong.song
        case .preview: preview.song
        case .embed, .provider: nil
        }
        return (song?.title ?? "Spielt gerade", song?.artist ?? "")
    }

    /// The one thing that stands out: in the accent colour, with the progress
    /// as a ring around it instead of a bar beside it.
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
                Circle().fill(Color.todAccent).padding(5)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.todBackground)
            }
            .frame(width: 52, height: 52)
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
        let playing: URL? = switch speaker {
        case .wholeSong: wholeSong.song?.artworkURL
        case .preview: preview.song?.artworkURL
        case .embed: embed.source?.artworkURL
        case .provider: store.currentlyPlaying?.artworkURL
        }
        return playing ?? post?.coverURL
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
