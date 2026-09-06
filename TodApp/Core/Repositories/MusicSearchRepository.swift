import Foundation

/// Kept for the sign-in screen's failure state: a provider that refuses
/// everything reads better than an optional nobody checks.
struct FailingMusicSearchRepository: Sendable {
    let error: TodAppError
    func searchTracks(matching query: String) async throws -> [TrackCandidate] { throw error }
}
