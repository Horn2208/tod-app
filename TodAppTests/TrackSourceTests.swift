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
}
