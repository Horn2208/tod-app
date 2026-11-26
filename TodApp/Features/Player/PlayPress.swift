import Foundation

/// What a press on play does, wherever the button sits: note the post for the
/// mini player, silence the other players on this phone, and toggle the one
/// this song plays in. The song's own player and the play button on a feed card
/// both press here, so the card cannot start a second sound beside the first.
@MainActor
struct PlayPress {
    let preview: PreviewPlayer
    let wholeSong: AppleMusicPlayer
    let embed: SpotifyEmbedPlayer
    let nowPlaying: NowPlaying
    /// SoundCloud's hidden player, silenced like the others.
    var soundCloud: SoundCloudEmbedPlayer? = nil
    /// The Spotify app through App Remote, silenced like the others.
    var remote: SpotifyRemote? = nil

    /// The five ways sound comes out. A new one goes here, and `silence`
    /// will not forget it.
    private enum Speaker {
        case preview, wholeSong, embed, soundCloud, spotifyApp
    }

    /// Every player but the one about to play.
    private func silence(except speaker: Speaker) {
        if speaker != .preview { preview.pause() }
        if speaker != .wholeSong { wholeSong.pause() }
        if speaker != .embed { embed.pause() }
        if speaker != .soundCloud { soundCloud?.pause() }
        if speaker != .spotifyApp { remote?.pause() }
    }

    func toggleWholeSong(_ song: CatalogSong, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        silence(except: .wholeSong)
        wholeSong.togglePlay(song, from: section)
    }

    func togglePreview(_ song: CatalogSong, post: Int?) {
        nowPlaying.submissionID = post
        silence(except: .preview)
        preview.togglePlay(song)
    }

    func toggleEmbed(_ source: TrackSource, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        silence(except: .embed)
        embed.togglePlay(source, startAt: section?.start)
    }

    func toggleSoundCloud(_ player: SoundCloudEmbedPlayer, _ source: TrackSource, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        silence(except: .soundCloud)
        player.togglePlay(source, startAt: section?.start)
    }

    /// The whole song in the Spotify app, from `start` (`SpotifyRemote`). The
    /// song Spotify already has is paused or resumed instead of started over.
    /// `onMissingApp` runs when the Spotify app is not there after all.
    func toggleInSpotify(
        _ remote: SpotifyRemote, _ source: TrackSource, from start: Double?, post: Int?,
        onMissingApp: @escaping @MainActor @Sendable () -> Void
    ) {
        if remote.isCurrent(source) {
            remote.togglePause()
            return
        }
        nowPlaying.submissionID = post
        silence(except: .spotifyApp)
        remote.play(source, from: start, onMissingApp: onMissingApp)
    }
}
