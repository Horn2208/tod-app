import Foundation
import Testing
@testable import TodApp

@Suite
struct SourceAttributionTests {
    private func post(service: MusicService?) -> Submission {
        let source = service.map {
            TrackSource(
                service: $0, serviceTrackID: "x",
                pageURL: URL(string: "https://open.spotify.com/track/x")!,
                artworkURL: nil
            )
        }
        return Submission(
            id: 1, posterID: "du", track: "Nights", artist: "Frank Ocean",
            coverColorHex: "#000000", comments: [], source: source
        )
    }

    @Test
    func aSpotifyFindShowsTheSpotifyMark() {
        #expect(SourceAttribution.foundViaSpotify(post(service: .spotify)))
    }

    @Test
    func aSongWithoutASpotifySourceDoesNot() {
        #expect(!SourceAttribution.foundViaSpotify(post(service: nil)))
        #expect(!SourceAttribution.foundViaSpotify(post(service: .soundcloud)))
        #expect(!SourceAttribution.foundViaSpotify(nil))
    }
}
