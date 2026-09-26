import Foundation

/// What a press on play does, wherever the button sits: note the post for the
/// mini player, silence the other two players on this phone, and toggle the one
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

    func toggleWholeSong(_ song: CatalogSong, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        preview.pause()
        embed.pause()
        soundCloud?.pause()
        remote?.pause()
        wholeSong.togglePlay(song, from: section)
    }

    func togglePreview(_ song: CatalogSong, post: Int?) {
        nowPlaying.submissionID = post
        embed.pause()
        wholeSong.pause()
        soundCloud?.pause()
        remote?.pause()
        preview.togglePlay(song)
    }

    func toggleEmbed(_ source: TrackSource, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        preview.pause()
        wholeSong.pause()
        soundCloud?.pause()
        remote?.pause()
        embed.togglePlay(source, startAt: section?.start)
    }

    func toggleSoundCloud(_ player: SoundCloudEmbedPlayer, _ source: TrackSource, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        preview.pause()
        wholeSong.pause()
        embed.pause()
        remote?.pause()
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
        preview.pause()
        wholeSong.pause()
        embed.pause()
        soundCloud?.pause()
        remote.play(source, from: start, onMissingApp: onMissingApp)
    }
}
