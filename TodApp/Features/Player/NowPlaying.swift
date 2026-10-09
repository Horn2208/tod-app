import Foundation
import Observation
import SwiftUI

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
    /// The song as the player sheet that started it knew it, for when there
    /// is no post to open: heard while posting, or from "Gemerkt". Set by
    /// `TrackPlayerSheet` when it starts playing.
    var item: Item?
    /// Whether the mini player's card is on screen, playing or lingering.
    /// Screens read it to keep their bottom clear of the card.
    var isCardShown = false

    /// Everything `TrackPlayerSheet` needs to show a song again.
    struct Item: Identifiable, Equatable {
        var title: String
        var artist: String
        var source: TrackSource?
        var section: TrackSection?
        var durationSeconds: Int?
        var appleMusicID: String?
        var isrc: String?
        var coverColorHex: String?

        var id: String {
            source.map { "\($0.service.rawValue):\($0.serviceTrackID)" } ?? "\(title)|\(artist)"
        }
    }
}

/// What a tap on the mini player opens. Never nothing while something plays:
/// a tap that did nothing -- a song heard while posting, a post no longer
/// loaded -- broke the app's rule "Kein Knopf ohne Wirkung" (the brief,
/// 8. Oktober, "Tipp auf den Mini-Player").
enum MiniPlayerTarget: Equatable {
    /// The post, with its player and comments.
    case song(Int)
    /// The player alone, for the song as it was started.
    case item
    case none

    static func target(submissionID: Int?, isLoaded: Bool, hasItem: Bool) -> MiniPlayerTarget {
        if let submissionID, isLoaded { return .song(submissionID) }
        return hasItem ? .item : .none
    }
}

extension View {
    /// The mini player's capsule as the place the big player grows out of
    /// (iOS 18 on; before, the sheet slides up as usual).
    @ViewBuilder
    func playerZoomSource(in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            matchedTransitionSource(id: "player", in: namespace)
        } else {
            self
        }
    }

    /// The big player, grown out of the mini player and shrunk back into it.
    @ViewBuilder
    func playerZoomDestination(in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            navigationTransition(.zoom(sourceID: "player", in: namespace))
        } else {
            self
        }
    }
}
