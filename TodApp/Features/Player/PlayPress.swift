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

    func toggleWholeSong(_ song: CatalogSong, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        preview.pause()
        embed.pause()
        wholeSong.togglePlay(song, from: section)
    }

    func togglePreview(_ song: CatalogSong, post: Int?) {
        nowPlaying.submissionID = post
        embed.pause()
        wholeSong.pause()
        preview.togglePlay(song)
    }

    func toggleEmbed(_ source: TrackSource, from section: TrackSection?, post: Int?) {
        nowPlaying.submissionID = post
        preview.pause()
        wholeSong.pause()
        embed.togglePlay(source, startAt: section?.start)
    }
}
