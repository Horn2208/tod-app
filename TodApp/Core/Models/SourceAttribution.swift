import Foundation

/// Which services a post should credit on the player and song cards.
///
/// Playback runs through Apple Music whenever a match exists, so the Apple
/// Music mark is always on. Spotify's mark is only for posts that were found
/// through a Spotify link or search -- `TrackSource.service`, not whichever
/// speaker is currently making sound.
enum SourceAttribution {
    static func foundViaSpotify(_ submission: Submission?) -> Bool {
        submission?.source?.service == .spotify
    }
}
