import Foundation
import Testing
@testable import TodApp

@Suite
struct FallbackCatalogTests {
    private let nights = CatalogSong(id: "1", title: "Nights", artist: "Frank Ocean", durationSeconds: 307)
    private let guess = CatalogSong(id: "2", title: "Nights", artist: "Frank Ocean", durationSeconds: 307)

    /// MusicKit throws until the account's service is on. Meanwhile the
    /// iTunes catalog answers, so previews keep playing.
    @Test
    func aThrowingPrimaryHandsOverToTheFallback() async throws {
        let catalog = FallbackCatalog(
            primary: FakeCatalog(failing: 1),
            fallback: FakeCatalog(hits: [nights]),
            usesPrimary: { true })

        #expect(try await catalog.search(title: "Nights", artist: "Frank Ocean") == [nights])
    }

    /// An empty answer is an answer. A primary that finds nothing must not be
    /// overruled by a weaker catalog's guess.
    @Test
    func anEmptyAnswerFromThePrimaryStands() async throws {
        let catalog = FallbackCatalog(
            primary: FakeCatalog(hits: []),
            fallback: FakeCatalog(hits: [guess]),
            usesPrimary: { true })

        #expect(try await catalog.search(title: "Nights", artist: "Frank Ocean").isEmpty)
    }

    /// Without the listener's permission MusicKit is not asked at all.
    @Test
    func aPrimaryNotInUseIsNeverAsked() async throws {
        let primary = FakeCatalog(hits: [guess])
        let catalog = FallbackCatalog(
            primary: primary, fallback: FakeCatalog(hits: [nights]), usesPrimary: { false })

        #expect(try await catalog.search(title: "Nights", artist: "Frank Ocean") == [nights])
        #expect(await primary.searches == 0)
    }
}
