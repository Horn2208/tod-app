import Foundation
import Testing
@testable import TodApp

@Suite
struct TrackSourceTests {
    @Test
    func candidateIDCombinesServiceAndTrackID() {
        let candidate = TrackCandidate(
            title: "Genesis",
            artist: "Justice",
            source: TrackSource(
                service: .spotify,
                serviceTrackID: "abc123",
                pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
                artworkURL: nil
            )
        )

        #expect(candidate.id == "spotify:abc123")
    }

    @Test
    func submissionWithoutSourceStillDecodes() throws {
        let json = Data("""
        {"id":1,"posterID":"du","track":"Genesis","artist":"Justice",
         "coverColorHex":"#b3527a","comments":[]}
        """.utf8)

        let submission = try JSONDecoder().decode(Submission.self, from: json)

        #expect(submission.source == nil)
        #expect(submission.track == "Genesis")
    }

    /// Battle carries a track like everything else, so it gets the same optional
    /// source -- and older stored battles that predate it must still decode.
    @Test
    func battleEntryWithoutSourceStillDecodes() throws {
        let json = Data("""
        {"name":"Mats","track":"Genesis","artist":"Justice",
         "coverColorHex":"#b3527a","percentage":52}
        """.utf8)

        let entry = try JSONDecoder().decode(BattleEntry.self, from: json)

        #expect(entry.source == nil)
        #expect(entry.track == "Genesis")
    }

    @Test
    func battleEntryKeepsItsSourceThroughARoundTrip() throws {
        let entry = BattleEntry(
            name: "Mats", track: "Genesis", artist: "Justice",
            coverColorHex: "#b3527a", percentage: 52,
            source: TrackSource(
                service: .spotify,
                serviceTrackID: "abc123",
                pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
                artworkURL: URL(string: "https://i.scdn.co/image/medium")
            )
        )

        let decoded = try JSONDecoder().decode(
            BattleEntry.self, from: JSONEncoder().encode(entry)
        )

        #expect(decoded.source?.artworkURL?.absoluteString == "https://i.scdn.co/image/medium")
    }
}
