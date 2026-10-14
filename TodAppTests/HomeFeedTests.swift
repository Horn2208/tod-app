import Foundation
import Testing
@testable import TodApp

@Suite
struct HomeFeedTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func song(_ id: Int, poster: String, minute: Int) -> Submission {
        Submission(
            id: id, posterID: poster, track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [],
            postedAt: noon.addingTimeInterval(Double(minute * 60)))
    }

    private var round: [Submission] {
        [
            song(1, poster: "lena", minute: 1),
            song(2, poster: "du", minute: 2),
            song(3, poster: "mats", minute: 3),
            song(4, poster: "ali", minute: 4),
        ]
    }

    @Test
    func ownSongFirstThenUnratedThenRated() {
        let ids = HomeFeed.pages(running: round, userID: "du", rated: [1]).map(\.id)

        #expect(ids == [2, 3, 4, 1])
    }

    @Test
    func withoutAnOwnSongTheUnratedLead() {
        let others = round.filter { $0.posterID != "du" }

        #expect(HomeFeed.pages(running: others, userID: "du", rated: [3]).map(\.id) == [1, 4, 3])
    }

    @Test
    func postingOrderHoldsWithinEachPart() {
        let shuffled = round.reversed().map { $0 }

        #expect(HomeFeed.pages(running: shuffled, userID: "du", rated: []).map(\.id) == [2, 1, 3, 4])
    }

    @Test
    func firstUnratedSkipsYourOwnAndTheRated() {
        let pages = HomeFeed.pages(running: round, userID: "du", rated: [])

        #expect(HomeFeed.firstUnrated(in: pages, userID: "du", rated: [1]) == 3)
        #expect(HomeFeed.firstUnrated(in: pages, userID: "du", rated: [1, 3, 4]) == nil)
    }

    @Test
    func rateLineCountsInSingularAndPlural() {
        #expect(HomeFeed.rateLine(toRate: 0) == nil)
        #expect(HomeFeed.rateLine(toRate: 1) == "1 Song wartet auf deine Bewertung")
        #expect(HomeFeed.rateLine(toRate: 2) == "2 Songs warten auf deine Bewertung")
    }
}
