import Foundation
import Observation

/// Finds the catalog song behind a posted track, once per track.
///
/// App-wide, so a song opened twice -- in the post sheet, then in the feed --
/// is asked about once. A verdict is remembered, a failed request is not:
/// "the catalog has no such song" is a fact about the song, a dropped
/// connection is not.
/// What a track is called when the catalog is asked about it.
enum CatalogKey {
    /// A posted link identifies a track exactly. A song without one is only
    /// its title and artist -- which is also all the catalog gets to work with,
    /// so two posts of the same song share one answer.
    static func of(source: TrackSource?, title: String, artist: String) -> String {
        if let source { return "\(source.service.rawValue):\(source.serviceTrackID)" }
        return "\(CatalogMatch.normalized(title))|\(CatalogMatch.normalized(artist))"
    }
}

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
    @ObservationIgnored private var verdicts: [String: Outcome] = [:]

    init(catalog: any MusicCatalog = ITunesCatalog()) {
        self.catalog = catalog
    }

    /// What is already known about this track, without asking anyone.
    func settled(for key: String) -> Outcome? {
        verdicts[key]
    }

    func resolve(
        key: String,
        title: String,
        artist: String,
        durationSeconds: Int?,
        knownID: String?
    ) async -> Outcome {
        if let known = verdicts[key] { return known }
        do {
            let outcome = try await lookUp(
                title: title, artist: artist, durationSeconds: durationSeconds, knownID: knownID)
            verdicts[key] = outcome
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
