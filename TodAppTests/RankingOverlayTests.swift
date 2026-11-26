import Foundation
import Testing
@testable import TodApp

@Suite
struct RankingOverlayTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func song(_ id: Int, poster: String, minute: Int = 0) -> Submission {
        Submission(
            id: id, posterID: poster, track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [],
            postedAt: day.addingTimeInterval(Double(minute * 60)))
    }

    private func score(_ id: Int, _ points: Int, gems: Int = 0) -> RoundScore {
        RoundScore(submissionID: id, points: points, hiddenGemCount: gems)
    }

    // MARK: When

    @Test
    func showsForAnUnseenRevealedDay() {
        #expect(RankingOverlay.shouldShowRanking(revealedDay: day, lastSeen: nil, isBlocked: false))
        #expect(RankingOverlay.shouldShowRanking(
            revealedDay: day, lastSeen: day.addingTimeInterval(-86_400), isBlocked: false))
    }

    @Test
    func staysAwayOnceSeenWithoutARevealOrWhileSomethingElseIsInFront() {
        #expect(!RankingOverlay.shouldShowRanking(revealedDay: day, lastSeen: day, isBlocked: false))
        #expect(!RankingOverlay.shouldShowRanking(revealedDay: nil, lastSeen: nil, isBlocked: false))
        #expect(!RankingOverlay.shouldShowRanking(revealedDay: day, lastSeen: nil, isBlocked: true))
    }

    // MARK: Order

    @Test
    func bestFirstWithTiesSharingAPlace() {
        let rows = RankingOverlay.ranking(
            scores: [score(1, 3), score(2, 5), score(3, 3), score(4, -1)],
            submissions: [song(1, poster: "a", minute: 1), song(2, poster: "b", minute: 2),
                          song(3, poster: "du", minute: 3), song(4, poster: "c", minute: 4)],
            userID: "du")

        #expect(rows.map(\.submission.id) == [2, 1, 3, 4])
        #expect(rows.map(\.place) == [1, 2, 2, 4])
        #expect(rows.map(\.isOwn) == [false, false, true, false])
    }

    @Test
    func aSongNobodyRatedScoresZeroInsteadOfVanishing() {
        let rows = RankingOverlay.ranking(
            scores: [score(1, -2)], submissions: [song(1, poster: "a"), song(2, poster: "b", minute: 1)],
            userID: "du")

        #expect(rows.map(\.submission.id) == [2, 1])
        #expect(rows.first?.points == 0)
    }

    // MARK: Words

    @Test
    func resultLineNamesYourPointsAndPlace() {
        let rows = RankingOverlay.ranking(
            scores: [score(1, 9), score(2, 7), score(3, 7)],
            submissions: [song(1, poster: "a"), song(2, poster: "b", minute: 1), song(3, poster: "du", minute: 2)],
            userID: "du")

        #expect(RankingOverlay.resultLine(rows) == "Dein Song: 7 Punkte · Platz 2 von 3")
        #expect(RankingOverlay.spokenSummary(rows)
            == "Gestern ist aufgedeckt. Dein Song: 7 Punkte, Platz 2 von 3.")
    }

    @Test
    func resultLineWithoutYourSongInvitesALook() {
        let rows = RankingOverlay.ranking(
            scores: [], submissions: (1...5).map { song($0, poster: "p\($0)", minute: $0) }, userID: "du")

        #expect(RankingOverlay.resultLine(rows) == "5 Songs, sieh dir an, wie bewertet wurde")
    }

    @Test
    func onePointIsSingular() {
        #expect(RankingOverlay.points(1) == "1 Punkt")
        #expect(RankingOverlay.points(-1) == "-1 Punkt")
        #expect(RankingOverlay.points(0) == "0 Punkte")
    }

    // MARK: Seen

    @Test
    func aSeenMarkIsPerGroup() throws {
        let defaults = try #require(UserDefaults(suiteName: "RankingOverlayTests"))
        defaults.removePersistentDomain(forName: "RankingOverlayTests")

        RankingSeenMarks.markSeen(day, in: "a", defaults: defaults)

        #expect(RankingSeenMarks.lastSeen(in: "a", defaults: defaults) == day)
        #expect(RankingSeenMarks.lastSeen(in: "b", defaults: defaults) == nil)
    }
}
