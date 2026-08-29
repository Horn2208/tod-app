import Foundation

/// The seam. Today this is backed by Spotify directly; once a proxy holds the
/// client secret, a ProxyMusicSearchRepository conforms to the same protocol
/// and only the AppStore init changes.
protocol MusicSearchRepository: Sendable {
    func searchTracks(matching query: String) async throws -> [TrackCandidate]
}
