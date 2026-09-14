import Observation

/// Which post the sound belongs to, so the mini player can open it again.
///
/// The players know what they play -- a track source, a catalog song -- but not
/// which post it came from: a preview is found by title or ISRC, and the same
/// recording can sit in two posts. So the player sheet says so at the moment
/// play is pressed, and nothing has to be worked out backwards.
@MainActor
@Observable
final class NowPlaying {
    /// Nil while what plays is not a post yet -- a song being picked in the
    /// post sheet.
    var submissionID: Int?
    /// Whether the mini player's card is on screen, playing or lingering.
    /// Screens read it to keep their bottom clear of the card.
    var isCardShown = false
}
