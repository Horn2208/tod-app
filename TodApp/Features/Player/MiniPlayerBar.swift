import MediaPlayer
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
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SpotifyRemote.self) private var remote
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    /// The post the sound belongs to, when there is one. It names the song the
    /// way the group saw it, and the Spotify mark follows how it was found.
    let post: Submission?
    /// Opens that post. Nil when there is none -- a song still being picked in
    /// the post sheet -- and the card then offers nothing to tap, rather than a
    /// tap that does nothing.
    let onOpen: (() -> Void)?
    /// The bottom bar's glass namespace, so the pill flows out of it.
    var glass: Namespace.ID? = nil
    /// Where the big player grows out of (iOS 18 on).
    var zoom: Namespace.ID? = nil

    /// Five things in this app can be making sound: a whole song from Apple
    /// Music, Apple's preview, Spotify's embed and SoundCloud's widget, all
    /// out of this phone, and the Spotify app through App Remote.
    private enum Speaker: Equatable {
        case wholeSong, preview, embed, soundCloud, remote
    }

    /// Whichever is actually running, those on this phone asked first.
    private var playing: Speaker? {
        if wholeSong.song != nil, !wholeSong.isPaused { return .wholeSong }
        if preview.song != nil, !preview.isPaused { return .preview }
        if embed.source != nil, !embed.isPaused { return .embed }
        if soundCloud.source != nil, !soundCloud.isPaused { return .soundCloud }
        if remote.trackURI != nil, !remote.isPaused { return .remote }
        return nil
    }

    /// What the card shows: the one playing, or for a moment after a pause the
    /// one that just stopped.
    @State private var shown: Speaker?
    @State private var pausedAt: Date?
    /// The cover as the system wants it, for the lock screen and the island.
    @State private var systemArtwork: MPMediaItemArtwork?
    @State private var remoteTargets: [Any] = []

    var body: some View {
        SwiftUI.Group {
            if let shown {
                card(shown)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: shown)
        // `initial` too: should this view ever be built afresh, its `shown`
        // starts empty, and the bar must hear that rather than stay apart
        // around nothing.
        .onChange(of: shown, initial: true) { _, now in nowPlaying.isCardShown = now != nil }
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
        .onChange(of: systemInfo, initial: true) { old, new in
            // Only ever cleared after we set it: Apple Music's player keeps
            // its own.
            if new != nil || old != nil { publish(new) }
        }
        .task(id: systemInfo == nil ? nil : shown.flatMap(artwork(of:))) {
            systemArtwork = nil
            guard systemInfo != nil, let url = shown.flatMap(artwork(of:)),
                  let image = await CoverImages.shared.image(for: url), !Task.isCancelled
            else { return }
            systemArtwork = Self.systemArtwork(image, size: image.size)
            publish(systemInfo)
        }
        .onAppear { remoteTargets = addRemoteCommands() }
        .onDisappear { removeRemoteCommands() }
    }

    // MARK: - Lock screen, Control Centre, Dynamic Island

    /// What the system shows for the sound this phone makes itself -- the
    /// preview, Spotify's embed, SoundCloud's widget -- instead of bare
    /// volume (the redesign brief, 26. September, point 4). Apple Music's
    /// player and the Spotify app tell the system themselves.
    private struct SystemInfo: Equatable {
        var track: String
        var artist: String
        /// Whole seconds: the system runs the clock on from here by itself.
        var position: Int
        var duration: Double
        var isPlaying: Bool
    }

    private var systemInfo: SystemInfo? {
        guard let shown, [.preview, .embed, .soundCloud].contains(shown) else { return nil }
        let names = names(of: shown)
        let time = time(of: shown)
        return SystemInfo(
            track: names.track, artist: names.artist,
            position: Int(time?.position ?? 0), duration: time?.duration ?? 0,
            isPlaying: playing == shown)
    }

    /// Off the main actor: the system asks for the image on a queue of its
    /// own, and a closure made in the view would trap there (crashed in the
    /// simulator, 26. September).
    nonisolated static func systemArtwork(_ image: UIImage, size: CGSize) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    private func publish(_ info: SystemInfo?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let info else {
            center.nowPlayingInfo = nil
            return
        }
        var now: [String: Any] = [
            MPMediaItemPropertyTitle: info.track,
            MPMediaItemPropertyArtist: info.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(info.position),
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
        ]
        if info.duration > 0 { now[MPMediaItemPropertyPlaybackDuration] = info.duration }
        if let systemArtwork { now[MPMediaItemPropertyArtwork] = systemArtwork }
        center.nowPlayingInfo = now
    }

    /// Play and pause from the lock screen and the island: the same as the
    /// card's own button.
    private func addRemoteCommands() -> [Any] {
        let commands = MPRemoteCommandCenter.shared()
        let wanted: [(MPRemoteCommand, Bool?)] = [
            (commands.playCommand, true), (commands.pauseCommand, false),
            (commands.togglePlayPauseCommand, nil),
        ]
        return wanted.map { command, play in
            command.addTarget { _ in
                MainActor.assumeIsolated {
                    guard systemInfo != nil, let shown else { return .noActionableNowPlayingItem }
                    let isPlaying = playing == shown
                    if play != isPlaying { toggle(shown, isPlaying: isPlaying) }
                    return .success
                }
            }
        }
    }

    private func removeRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand] {
            for target in remoteTargets { command.removeTarget(target) }
        }
        remoteTargets = []
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
        // One height with the round Home and Gruppen buttons beside it
        // (`RootNavBar`).
        .frame(height: RootNavBar.itemHeight)
        .background {
            // The cover's colour, faint, behind the frosted glass. Liquid
            // Glass takes its colour from what lies behind it by itself.
            if !LiquidGlass.isAvailable {
                CrossfadeCover(url: artwork(of: speaker), placeholder: Color.todSurface3)
                .opacity(0.35)
                .blur(radius: 16)
                .accessibilityHidden(true)
            }
        }
        .liquidGlass(in: Capsule(), id: "player", namespace: glass, interactive: false)
        .clipShape(Capsule())
        // The whole capsule opens the song, its rim included; only the play
        // button keeps to itself (a button wins over the tap around it).
        .contentShape(Capsule())
        .onTapGesture { onOpen?() }
        .playerZoomSource(in: zoom)
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

    /// From the shared cache (`CoverImages`), and kept on screen while a new
    /// one loads: `AsyncImage` started over whenever the card was redrawn,
    /// and a load cut short left the bare colour standing.
    private func cover(_ speaker: Speaker) -> some View {
        CrossfadeCover(
            url: artwork(of: speaker),
            placeholder: post.map { Color(hex: $0.coverColorHex) } ?? Color.todSurface3)
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.todLine, lineWidth: 0.5))
    }

    /// Which service is making the sound, small beside the artist. Apple's mark
    /// for a whole song or a preview, Spotify's for the embed and the Spotify
    /// app, and Spotify's too for a post that was found through Spotify.
    private func sourceIcons(_ speaker: Speaker) -> some View {
        let viaApple = speaker == .wholeSong || speaker == .preview
        let viaSpotify = speaker == .embed || speaker == .remote
            || SourceAttribution.foundViaSpotify(post)
        // The services' own icons (`BrandIcon`), apart by half the Spotify
        // icon's height -- the clear space Spotify asks for.
        return HStack(spacing: 7) {
            if viaApple {
                BrandIcon(brand: .appleMusic, size: 14)
            }
            if viaSpotify {
                BrandIcon(brand: .spotify, size: 14)
            }
        }
        .accessibilityHidden(true)
    }

    /// The post's names where there is a post; otherwise what the catalog
    /// calls the song. The embeds and the Spotify app report neither.
    private func names(of speaker: Speaker) -> (track: String, artist: String) {
        if let post { return (post.track, post.artist) }
        // Heard while posting: the names the player sheet had, as long as it
        // is still that song playing.
        if let item = nowPlaying.item, let source = item.source,
           source == (speaker == .embed ? embed.source : speaker == .soundCloud ? soundCloud.source : nil) {
            return (item.title, item.artist)
        }
        let song: CatalogSong? = switch speaker {
        case .wholeSong: wholeSong.song
        case .preview: preview.song
        case .embed, .soundCloud, .remote: nil
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
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
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
        case .soundCloud:
            if isPlaying {
                soundCloud.pause()
            } else if let source = soundCloud.source {
                soundCloud.togglePlay(source)
            }
        case .remote:
            remote.togglePause()
        }
    }

    private func artwork(of speaker: Speaker) -> URL? {
        let playing: URL? = switch speaker {
        case .wholeSong: wholeSong.song?.artworkURL
        case .preview: preview.song?.artworkURL
        case .embed: embed.source?.artworkURL
        case .soundCloud: soundCloud.source?.artworkURL
        // The cover of the song this app asked the Spotify app to play;
        // Spotify's own report carries none.
        case .remote: remote.artworkURL
        }
        return playing ?? post?.coverURL
    }

    /// Position and length, where the speaker reports them.
    private func time(of speaker: Speaker) -> (position: Double, duration: Double)? {
        switch speaker {
        case .wholeSong where wholeSong.duration > 0: (wholeSong.position, wholeSong.duration)
        case .preview where preview.duration > 0: (preview.position, preview.duration)
        case .embed where embed.duration > 0: (embed.position, embed.duration)
        case .soundCloud where soundCloud.duration > 0: (soundCloud.position, soundCloud.duration)
        case .remote where remote.duration > 0: (remote.position, remote.duration)
        default: nil
        }
    }
}
