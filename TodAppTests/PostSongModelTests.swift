import Foundation
import Testing
@testable import TodApp

struct MockMusicSearchRepository: MusicSearchRepository {
    var candidates: [TrackCandidate] = []
    var error: TodAppError?
    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        if let error { throw error }
        return candidates
    }
}

@Suite
@MainActor
struct PostSongModelTests {
    private func candidate(_ id: String) -> TrackCandidate {
        TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: id,
                pageURL: URL(string: "https://open.spotify.com/track/\(id)")!, artworkURL: nil
            )
        )
    }

    @Test
    func searchPopulatesResults() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.map(\.id) == ["spotify:a"])
        #expect(model.isSearching == false)
    }

    @Test
    func missingCredentialsProduceAnActionableMessage() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .missingSpotifyCredentials),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage?.contains("Secrets.xcconfig") == true)
    }

    @Test
    func rateLimitIsReportedSeparatelyFromOtherFailures() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .rateLimited), debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.errorMessage?.contains("zu viele") == true)
    }

    @Test
    func clearingTheQueryClearsResultsAndError() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]), debounce: .zero
        )
        await model.queryChanged("justice")

        await model.queryChanged("")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func unrecognisedLinkIsReportedAtTheField() async {
        let model = PostSongModel(search: MockMusicSearchRepository(), debounce: .zero)

        await model.linkTextChanged("einfach nur text")

        #expect(model.selected == nil)
        #expect(model.errorMessage?.isEmpty == false)
    }

    @Test
    func spotifyLinkSelectsCandidateWithoutNetworkCall() async {
        let model = PostSongModel(search: MockMusicSearchRepository(), debounce: .zero)

        await model.linkTextChanged("https://open.spotify.com/track/abc123")

        #expect(model.selected?.source.serviceTrackID == "abc123")
        #expect(model.errorMessage == nil)
    }
}
