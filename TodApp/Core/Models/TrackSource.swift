import Foundation

enum MusicService: String, Codable, Hashable {
    case spotify, soundcloud
}

/// Where a submitted track actually lives. Display truth stays on
/// `Submission.track` / `.artist`, so lists still render if a service is down.
struct TrackSource: Codable, Hashable {
    var service: MusicService
    var serviceTrackID: String
    var pageURL: URL
    var artworkURL: URL?
}

/// A search hit or a resolved link, before it becomes a Submission.
struct TrackCandidate: Identifiable, Hashable {
    var id: String { "\(source.service.rawValue):\(source.serviceTrackID)" }
    var title: String
    var artist: String
    var source: TrackSource
    /// Whole seconds. Nil when the service did not say -- SoundCloud's oEmbed
    /// does not carry a length, and the picker then works from an assumption
    /// it admits to.
    var durationSeconds: Int?
}
