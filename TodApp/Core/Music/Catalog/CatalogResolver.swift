import Foundation
import Observation

/// Finds the catalog song behind a posted track, once per track.
///
/// App-wide, so a song opened twice -- in the post sheet, then in the feed --
/// is asked about once. A verdict is remembered, a failed request is not:
/// "the catalog has no such song" is a fact about the song, a dropped
/// connection is not.
@MainActor
@Observable
final class CatalogResolver {
    enum Outcome: Equatable, Sendable {
        case found(CatalogSong)
        case notInCatalog

        var song: CatalogSong? {
            if case .found(let song) = self { return song }
            return nil
        }
    }

    private let catalog: any MusicCatalog
    @ObservationIgnored private var verdicts: [TrackSource: Outcome] = [:]

    init(catalog: any MusicCatalog = ITunesCatalog()) {
        self.catalog = catalog
    }

    /// What is already known about this track, without asking anyone.
    func settled(for source: TrackSource) -> Outcome? {
        verdicts[source]
    }

    func resolve(
        source: TrackSource,
        title: String,
        artist: String,
        durationSeconds: Int?,
        knownID: String?
    ) async -> Outcome {
        if let known = verdicts[source] { return known }
        do {
            let outcome = try await lookUp(
                title: title, artist: artist, durationSeconds: durationSeconds, knownID: knownID)
            verdicts[source] = outcome
            return outcome
        } catch {
            // Not remembered: next time the song opens, it is asked again.
            return .notInCatalog
        }
    }

    private func lookUp(
        title: String, artist: String, durationSeconds: Int?, knownID: String?
    ) async throws -> Outcome {
        // An id stored with the post is the match made when it went up. Asking
        // for it again is cheaper, and cannot land on a different recording.
        if let knownID, let song = try await catalog.song(id: knownID) {
            return .found(song)
        }
        let hits = try await catalog.search(title: title, artist: artist)
        let wanted = CatalogMatch.Wanted(title: title, artist: artist, durationSeconds: durationSeconds)
        return CatalogMatch.best(for: wanted, among: hits).map(Outcome.found) ?? .notInCatalog
    }
}
