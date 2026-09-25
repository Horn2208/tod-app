import SwiftUI

/// What the play button on a feed card does, by the route the song's own
/// player would take (`TrackPlayerSheet.player`).
enum QuickPlay {
    enum Action: Equatable {
        /// The catalog has not answered yet: shown, not pressable.
        case wait
        case wholeSong, preview, embed
        /// SoundCloud plays only in its own widget, and a song with nothing to
        /// play has nothing to start -- no button, the cover still opens it.
        case hidden
    }

    static func action(for route: TrackPlayerSheet.Player) -> Action {
        switch route {
        case .waiting: .wait
        case .appleMusic: .wholeSong
        case .applePreview: .preview
        case .own: .embed
        case .widget, .none: .hidden
        }
    }

    /// Whether a press plays the service's short preview rather than the
    /// picked stretch -- marked on the button, so a different excerpt reads as
    /// how the service works, not as a fault. Never for a whole song; always
    /// for Spotify's embed, which plays signed out (`SpotifyEmbedPlayer`).
    static func playsPreview(_ action: Action) -> Bool {
        switch action {
        case .preview, .embed: true
        case .wholeSong, .wait, .hidden: false
        }
    }
}

/// Play and pause right on a feed card, to listen in while rating without
/// opening the song. The same route and the same players as the song's own
/// player (`PlayPress`), so what starts here is what the mini player shows,
/// and opening the song afterwards finds it already playing.
struct QuickPlayButton: View {
    let submission: Submission

    @Environment(CatalogResolver.self) private var catalog
    @Environment(AppleMusicAccess.self) private var appleMusic
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    /// What the catalog said about this song. Nil while it has not answered.
    @State private var outcome: CatalogResolver.Outcome?

    private var key: String {
        CatalogKey.of(source: submission.source, title: submission.track, artist: submission.artist)
    }

    private var action: QuickPlay.Action {
        QuickPlay.action(for: TrackPlayerSheet.player(
            for: submission.source?.service, catalog: outcome,
            appleMusicWholeSongs: appleMusic.playsWholeSongs))
    }

    private var press: PlayPress {
        PlayPress(preview: preview, wholeSong: wholeSong, embed: embed, nowPlaying: nowPlaying, soundCloud: soundCloud)
    }

    /// Whether this song is the one sounding, how far it has got -- nil when
    /// it is not this song's turn -- and whether a press can do anything yet.
    private var state: (isPlaying: Bool, progress: Double?, isEnabled: Bool) {
        switch action {
        case .wholeSong:
            guard let song = outcome?.song else { return (false, nil, false) }
            let isMine = wholeSong.songID == song.id
            return (wholeSong.isPlaying(song.id), isMine ? wholeSong.progress : nil, true)
        case .preview:
            guard let song = outcome?.song else { return (false, nil, false) }
            let isMine = preview.songID == song.id
            // A failed load is tried again on the press (`PreviewPlayer.load`).
            return (preview.isPlaying(song.id), isMine ? preview.progress : nil, song.previewURL != nil)
        case .embed:
            guard let source = submission.source else { return (false, nil, false) }
            let isMine = embed.source == source
            return (embed.isPlaying(source), isMine ? embed.progress : nil, embed.status == .ready)
        case .wait, .hidden:
            return (false, nil, false)
        }
    }

    var body: some View {
        SwiftUI.Group {
            if action != .hidden {
                button
            }
        }
        // The same lookup as the song's own player, answered from the cache
        // when the song has been open before.
        .task(id: key) {
            outcome = catalog.settled(for: key)
            guard outcome == nil, TrackPlayerSheet.looksUpCatalog(for: submission.source?.service) else { return }
            outcome = await catalog.resolve(
                key: key, title: submission.track, artist: submission.artist,
                durationSeconds: submission.durationSeconds, knownID: submission.appleMusicID,
                isrc: submission.isrc)
        }
    }

    /// The preview of this song failed to load; a press tries again.
    private var hasFailed: Bool {
        action == .preview && preview.songID == outcome?.song?.id && preview.failure != nil
    }

    /// A press plays the service's short preview, not the picked stretch.
    private var playsPreview: Bool { QuickPlay.playsPreview(action) }

    /// Small and quiet beside the button: the excerpt is how the service works,
    /// not a fault. Tapping the cover opens the song, where the player says
    /// more.
    private var previewMark: some View {
        Text("30s")
            .font(.todMono(9, weight: .semibold))
            .foregroundStyle(Color.todTextFaint)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.todBackground.opacity(0.85), in: Capsule())
            .offset(x: -12, y: -6)
            .accessibilityHidden(true)
    }

    private var button: some View {
        let state = state
        let playsPreview = playsPreview
        return Button(action: toggle) {
            ZStack {
                Circle().fill(Color.todAccent)
                if let progress = state.progress, progress > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(Color.todAccent2, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                }
                if action == .wait {
                    ProgressView()
                        .tint(Color.todBackground)
                } else {
                    Image(systemName: hasFailed ? "arrow.clockwise"
                          : state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.todBackground)
                }
            }
            .frame(width: 50, height: 50)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .overlay(alignment: .topLeading) {
                if playsPreview { previewMark }
            }
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .animation(.snappy, value: state.isPlaying)
        .accessibilityLabel(action == .wait ? "Player lädt"
                            : hasFailed ? "Vorschau lädt nicht, nochmal versuchen"
                            : state.isPlaying ? "Pause"
                            : "\(Spoken.song(track: submission.track, artist: submission.artist)) abspielen"
                              + (playsPreview ? ", kurze Vorschau" : ""))
    }

    private func toggle() {
        switch action {
        case .wholeSong:
            if let song = outcome?.song {
                press.toggleWholeSong(song, from: submission.section, post: submission.id)
            }
        case .preview:
            if let song = outcome?.song {
                press.togglePreview(song, post: submission.id)
            }
        case .embed:
            if let source = submission.source {
                press.toggleEmbed(source, from: submission.section, post: submission.id)
            }
        case .wait, .hidden:
            break
        }
    }
}
