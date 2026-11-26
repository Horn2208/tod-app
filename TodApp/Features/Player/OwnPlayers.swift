import SwiftUI

// The player for each way a song plays, picked by `TrackPlayerSheet.player`.

/// This app's own transport for a Spotify track: a progress line and one
/// button, in this app's colours, on top of an embed nobody sees. The same
/// controls for everyone -- Spotify decides whether 30 seconds or the whole
/// song comes out, and that decision follows the web view's login state, not
/// anything here.
struct SpotifyOwnPlayer: View {
    @Environment(SpotifyRemote.self) private var remote
    @Environment(SpotifyEmbedPlayer.self) private var player
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    let source: TrackSource
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.source == source }
    private var isPlaying: Bool { isMine && !player.isPaused }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // A player that is not ready must say so. Silently accepting taps
            // and doing nothing is how this looked while the controller had
            // not answered, and it is indistinguishable from a broken app.
            switch player.status {
            case .failed(let message):
                Text(message)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            case .idle, .loading:
                Text("Player lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            case .ready:
                if isMine, let error = player.embedError {
                    Text(error)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todAccent2)
                } else if isMine, player.isStarting {
                    // The tap registered; the embed is still loading the
                    // track. Said, so the button does not look ignored.
                    Text("Startet …")
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextFaint)
                }
            }

            if isMine, let section {
                if player.isSectionHearable == false {
                    // Measured, not assumed: Spotify reported a length that is
                    // the excerpt's, so the start the poster picked is not in
                    // what is playing.
                    PlayerHintLine(hint: .spotifyExcerpt(sectionStart: section.start))
                } else {
                    Text("Abschnitt ab \(TrackPlayerSheet.timestamp(section.start))")
                        .font(.todMono(12, weight: .semibold))
                        .foregroundStyle(Color.todTextFaint)
                }
            }

            Transport(
                waveformSeed: source.serviceTrackID,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: isPlaying,
                position: isMine ? player.position : 0,
                duration: isMine ? player.duration : 0,
                isEnabled: player.status == .ready,
                toggle: {
                    PlayPress(preview: preview, wholeSong: wholeSong, embed: player, nowPlaying: nowPlaying, soundCloud: soundCloud, remote: remote)
                        .toggleEmbed(source, from: section, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                },
                skip: { seconds in
                    guard isMine, let to = PlaybackSkip.target(
                        position: player.position, by: seconds, duration: player.duration)
                    else { return }
                    player.seek(to: to)
                }
            )
        }
        .multilineTextAlignment(.center)
        // Points the shared player at this track without starting it: opening
        // a song must not start noise by itself.
        .task(id: source) {
            // Only while nothing else is playing. Loading swaps the embed's
            // track, which silences whatever it had -- so opening a second
            // song used to stop the first before play was even pressed, and
            // took the mini player with it. With something playing, the press
            // on play does the loading instead: `togglePlay` loads and plays.
            guard preview.isPaused, player.isPaused || player.source == source else { return }
            player.load(source, startAt: section?.start)
        }
    }
}

/// Apple's preview, played natively. Honest about what it is: a fixed excerpt
/// Apple chooses, so a picked section may well lie outside it.
struct ApplePreviewPlayer: View {
    @Environment(SpotifyRemote.self) private var remote
    @Environment(PreviewPlayer.self) private var player
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    let song: CatalogSong
    let waveformSeed: String
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.songID == song.id }
    private var failure: String? { isMine ? player.failure : nil }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if let failure {
                Text(failure)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            } else if isMine, player.duration == 0 {
                // The item is not ready yet -- once it took nine seconds. A
                // press in that time plays when it is; until then, say so,
                // rather than a pause symbol over silence.
                Text("Vorschau lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            if let section {
                PlayerHintLine(hint: .applePreview(sectionStart: section.start))
            }

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: player.isPlaying(song.id),
                position: isMine ? player.position : 0,
                duration: isMine ? player.duration : 0,
                // A failed load is tried again on the press; only a song
                // without a preview has nothing to try.
                isEnabled: song.previewURL != nil,
                toggle: {
                    PlayPress(preview: player, wholeSong: wholeSong, embed: embed, nowPlaying: nowPlaying, soundCloud: soundCloud, remote: remote)
                        .togglePreview(song, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                },
                skip: { seconds in
                    guard isMine, let to = PlaybackSkip.target(
                        position: player.position, by: seconds, duration: player.duration)
                    else { return }
                    player.seek(to: to)
                }
            )
            // Apple's terms for previews ask for a way to the song in its store:
            // the "Music öffnen" pill under the player.
        }
        .multilineTextAlignment(.center)
        .task(id: song.id) {
            // The same rule as the embed's: looking at a song must not silence
            // the one already playing. The play button loads it when pressed,
            // and pauses the embed then.
            guard embed.isPaused, player.isPaused || player.songID == song.id else { return }
            player.load(song)
        }
    }
}

/// A whole song from Apple Music, started at the picked section -- for a
/// listener whose subscription plays catalog songs; everyone else gets the
/// preview. Nothing is queued when the song opens, because queueing silences
/// whatever is playing. The press on play does it.
/// SoundCloud through its hidden widget (`SoundCloudEmbedPlayer`), under the
/// app's own waveform, play button and time -- like Spotify's embed, and
/// starting at the picked section, which SoundCloud's visible widget cannot.
///
/// SoundCloud's API Terms (section 8) ask for the uploader, SoundCloud as the
/// source and a visible link to the sound -- the line under the controls.
struct SoundCloudOwnPlayer: View {
    @Environment(SpotifyRemote.self) private var remote
    @Environment(\.openURL) private var openURL
    @Environment(SoundCloudEmbedPlayer.self) private var player
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    let source: TrackSource
    /// Who uploaded it: SoundCloud's author name, stored as the post's artist.
    let uploader: String
    let waveformSeed: String
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.source == source }

    /// Uploader and source, and a way to the sound on soundcloud.com.
    private var attribution: some View {
        Button {
            openURL(source.pageURL)
        } label: {
            HStack(spacing: 6) {
                // SoundCloud's own wordmark, white for a dark ground, as its
                // guidelines hand it out; well over their 30-pixel minimum.
                Image("SoundCloudLogoWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .accessibilityHidden(true)
                if let credit = SoundCloudAttribution.uploaderCredit(uploader) {
                    Text(credit)
                        .font(.todBody(12, weight: .semibold))
                        .lineLimit(1)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.todTextDim)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(SoundCloudAttribution.text(uploader: uploader)), auf soundcloud.com öffnen")
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if isMine, player.status == .loading {
                Text("Player lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            } else if let section {
                Text("Abschnitt ab \(TrackPlayerSheet.timestamp(section.start))")
                    .font(.todMono(12, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
            }

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: player.isPlaying(source),
                position: isMine ? player.position : 0,
                duration: isMine ? player.duration : 0,
                isEnabled: true,
                toggle: {
                    PlayPress(preview: preview, wholeSong: wholeSong, embed: embed, nowPlaying: nowPlaying, remote: remote)
                        .toggleSoundCloud(player, source, from: section, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                },
                skip: { seconds in
                    guard isMine, let to = PlaybackSkip.target(
                        position: player.position, by: seconds, duration: player.duration)
                    else { return }
                    player.seek(to: to)
                }
            )

            attribution
        }
        .multilineTextAlignment(.center)
        // Points the player at this track without starting it, while nothing
        // else of SoundCloud's plays.
        .task(id: source) {
            guard player.isPaused || player.source == source else { return }
            player.load(source, startAt: section?.start)
        }
    }
}

/// Before the Spotify app plays the song: the same controls, and play starts
/// it there, whole, from the section. A tap on the waveform starts it from
/// that point instead. Once Spotify reports the song, `SpotifyRemotePlayer`
/// takes over.
struct SpotifyAppStartPlayer: View {
    let waveformSeed: String
    /// Off while posting, where the section picker is the waveform.
    let showsWaveform: Bool
    let section: TrackSection?
    /// The song's length, or the assumed one -- for the waveform and the time.
    let duration: Double
    /// Seconds to start from; nil for the very start.
    let start: (Double?) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(section.map { "Ganzer Song in Spotify ab \(TrackPlayerSheet.timestamp($0.start))" }
                 ?? "Ganzer Song in Spotify")
                .font(.todMono(12, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: 0,
                isPlaying: false,
                position: 0,
                duration: duration,
                isEnabled: true,
                toggle: { start(section?.start) },
                seek: { fraction in start(fraction * duration) },
                skip: { _ in },
                showsSkips: false
            )
        }
        .multilineTextAlignment(.center)
    }
}

/// What the Spotify app plays, through App Remote: Spotify's own position on
/// the waveform, and the buttons steering Spotify.
struct SpotifyRemotePlayer: View {
    @Environment(SpotifyRemote.self) private var remote
    let source: TrackSource
    let waveformSeed: String
    let showsWaveform: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(remote.isConnected ? "Ganzer Song, spielt in Spotify" : "Ganzer Song in Spotify · verbindet …")
                .font(.todMono(12, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: remote.progress,
                isPlaying: !remote.isPaused,
                position: remote.position,
                duration: remote.duration,
                isEnabled: true,
                toggle: { remote.togglePause() },
                seek: { fraction in
                    guard remote.duration > 0 else { return }
                    remote.seek(to: fraction * remote.duration)
                },
                skip: { _ in },
                showsSkips: false
            )
        }
        .multilineTextAlignment(.center)
    }
}

struct AppleWholeSongPlayer: View {
    @Environment(SpotifyRemote.self) private var remote
    @Environment(AppleMusicPlayer.self) private var player
    @Environment(PreviewPlayer.self) private var preview
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    let song: CatalogSong
    let waveformSeed: String
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.songID == song.id }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if isMine, let failure = player.failure {
                Text(failure)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            } else if isMine, player.isStarting {
                // Fetching and queueing takes a moment. Said, so the press
                // does not look ignored.
                Text("Startet …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            if let section {
                Text("Ganzer Song, ab \(TrackPlayerSheet.timestamp(section.start))")
                    .font(.todMono(12, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
            }

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: player.isPlaying(song.id),
                position: isMine ? player.position : 0,
                // The catalog knows the length before anything is queued, so
                // the clock can say it from the start.
                duration: isMine ? player.duration : Double(song.durationSeconds ?? 0),
                isEnabled: true,
                toggle: {
                    PlayPress(preview: preview, wholeSong: player, embed: embed, nowPlaying: nowPlaying, soundCloud: soundCloud, remote: remote)
                        .toggleWholeSong(song, from: section, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                },
                skip: { seconds in
                    guard isMine, let to = PlaybackSkip.target(
                        position: player.position, by: seconds, duration: player.duration)
                    else { return }
                    player.seek(to: to)
                }
            )
        }
        .multilineTextAlignment(.center)
    }
}
