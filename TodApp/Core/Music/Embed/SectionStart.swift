import Foundation

/// What to do with the start a poster picked, once Spotify has said what it is
/// actually delivering.
///
/// With a Spotify session in the app's web view the start goes into the load
/// and should simply be there. Whether it can be is not the app's call:
/// signed in with Premium, the embed plays the whole song; without that,
/// Spotify hands over a short excerpt it chose itself. Where that excerpt sits
/// in the song is Spotify's choice and not reported, so a picked start -- a
/// time in the song -- cannot be mapped onto it at all, not even an early one.
/// Decided from the first report of position and length, not from what the
/// account claims to be.
enum SectionStart {
    enum Decision: Equatable {
        /// Playback is already at the picked start.
        case inPlace
        /// The start lies in what is playing, but playback is elsewhere -- the
        /// load did not take the timestamp. Move there.
        case seek(to: Double)
        /// What plays is the excerpt, or the start lies past the end: the
        /// picked start is not in it. Nothing to seek to; say so instead.
        case outsideWhatPlays
    }

    /// Spotify's excerpts are at most thirty seconds -- 30 and 22 have both
    /// been measured. Anything that long or shorter is treated as the excerpt.
    /// A genuinely shorter whole song would be misread; that is accepted.
    static let excerptLength: Double = 30.5

    /// Within this many seconds of the start counts as there: the first report
    /// arrives a moment after playback began.
    static let tolerance: Double = 2

    static func decide(start: Double, position: Double, duration: Double) -> Decision {
        guard duration > excerptLength else { return .outsideWhatPlays }
        guard start < duration - 1 else { return .outsideWhatPlays }
        return abs(position - start) <= tolerance ? .inPlace : .seek(to: start)
    }
}
