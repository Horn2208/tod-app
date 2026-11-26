import Foundation
import Supabase
import Testing
@testable import TodApp

/// The small rules between the app and the database: which day a round is,
/// how a round's rows add up, and what a server's refusal means to a person.
@Suite
struct RoundDayTests {
    private func berlin() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    @Test
    func aDayIsWrittenAsTheDatabaseWritesIt() {
        let calendar = berlin()
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!

        #expect(RoundDay.string(for: date, calendar: calendar) == "2026-03-07")
    }

    /// A minute before midnight is still the old day, and the database
    /// agrees, because it counts in Berlin too.
    @Test
    func midnightInBerlinSeparatesTwoRounds() {
        let calendar = berlin()
        let before = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 59))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 1))!

        #expect(RoundDay.berlin(before) == "2026-09-30")
        #expect(RoundDay.berlin(after) == "2026-10-01")
    }

    /// 22:30 UTC on 30 September is already 1 October in Berlin (summer time).
    @Test
    func theDatabasesDayIsBerlinsNotUTCs() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let late = utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 22, minute: 30))!

        #expect(RoundDay.berlin(late) == "2026-10-01")
    }

    /// A phone set to the Buddhist calendar counts 2569; the database does not.
    @Test
    func theYearIsAlwaysGregorian() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = berlin().date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!

        #expect(RoundDay.string(for: date, calendar: buddhist) == "2026-09-17")
    }
}

@Suite
struct ScoreTallyTests {
    private func vote(_ submission: Int, _ voter: String, _ rating: Int, note: String? = nil) -> VoteRecord {
        VoteRecord(
            submissionID: submission, groupID: "g", roundDay: "2026-09-16", voterID: voter,
            rating: rating, note: note)
    }

    private func gem(_ submission: Int, _ voter: String) -> GemRecord {
        GemRecord(voterID: voter, groupID: "g", roundDay: "2026-09-16", submissionID: submission)
    }

    @Test
    func ratingsAddUpPerSong() {
        let scores = ScoreTally.scores(
            submissionIDs: [1, 2],
            votes: [vote(1, "a", 2), vote(1, "b", -1), vote(2, "a", 1)],
            gems: [])

        #expect(scores.map(\.submissionID) == [1, 2])
        #expect(scores.map(\.points) == [1, 1])
    }

    /// Nobody rated it: it scored zero, and it is still in the round.
    @Test
    func anUnratedSongScoresZero() {
        let scores = ScoreTally.scores(submissionIDs: [1, 2], votes: [vote(1, "a", 2)], gems: [])

        #expect(scores.map(\.points) == [2, 0])
    }

    @Test
    func gemsAreCountedWithoutMovingThePoints() {
        let scores = ScoreTally.scores(
            submissionIDs: [1],
            votes: [vote(1, "a", -2)],
            gems: [gem(1, "a"), gem(1, "b")])

        #expect(scores.first?.points == -2)
        #expect(scores.first?.hiddenGemCount == 2)
    }

    /// Rows for a song outside the round (another day, another group) are
    /// not this round's business.
    @Test
    func rowsForOtherSongsAreIgnored() {
        let scores = ScoreTally.scores(
            submissionIDs: [1],
            votes: [vote(1, "a", 1), vote(9, "a", 2)],
            gems: [gem(9, "a")])

        #expect(scores.count == 1)
        #expect(scores.first?.points == 1)
        #expect(scores.first?.hiddenGemCount == 0)
    }

    @Test
    func aVoteRecordBecomesAVote() {
        let converted = vote(4, "a", -1, note: "zu lang").vote

        #expect(converted?.submissionID == 4)
        #expect(converted?.voterID == "a")
        #expect(converted?.rating == .meh)
        #expect(converted?.note == "zu lang")
        #expect(converted?.isHiddenGem == false)
    }

    /// The database allows -2 to 2; anything else is not a rating the app
    /// can show, so it is left out rather than guessed.
    @Test
    func anImpossibleRatingIsNoVote() {
        #expect(vote(4, "a", 3).vote == nil)
    }
}

@Suite
struct BackendErrorTests {
    private func mapped(_ error: Error, _ context: BackendError.Context) -> TodAppError? {
        BackendError.map(error, context: context) as? TodAppError
    }

    private func refused(_ code: String) -> PostgrestError {
        PostgrestError(code: code, message: "refused")
    }

    /// Row level security refusing a vote means the round moved on -- after
    /// midnight, today's policy no longer matches yesterday's song.
    @Test
    func aRefusedVoteMeansTheRoundIsOver() {
        #expect(mapped(refused("42501"), .vote) == .roundClosed)
    }

    @Test
    func aRefusalElsewhereMeansNotAllowed() {
        #expect(mapped(refused("42501"), .write) == .notAllowed)
        #expect(mapped(refused("42501"), .post) == .notAllowed)
    }

    /// One song a day per person per group: the unique key says no.
    @Test
    func aSecondPostTheSameDayIsAlreadyPosted() {
        #expect(mapped(refused("23505"), .post) == .alreadyPosted)
    }

    @Test
    func anUnknownOrExpiredCodeIsAnInvalidInvite() {
        #expect(mapped(refused("P0002"), .join) == .inviteInvalid)
    }

    @Test
    func aMissingRowIsNotFound() {
        #expect(mapped(refused("PGRST116"), .read) == .notFound)
        #expect(mapped(refused("P0002"), .read) == .notFound)
    }

    /// A token the server no longer takes is an account problem, not the
    /// network's.
    @Test
    func anExpiredTokenIsASignInProblem() {
        #expect(mapped(refused("PGRST303"), .read) == .accountSignInFailed)
        #expect(mapped(AuthError.sessionMissing, .write) == .accountSignInFailed)
    }

    @Test
    func storageRefusalsAreReadByStatus() {
        #expect(mapped(StorageError(statusCode: "403", message: "rls"), .write) == .notAllowed)
        #expect(mapped(StorageError(statusCode: "404", message: "gone"), .read) == .notFound)
    }

    @Test
    func aTodAppErrorPassesThrough() {
        #expect(mapped(TodAppError.roundClosed, .read) == .roundClosed)
    }

    @Test
    func anythingElseIsTheNetwork() {
        let lost = BackendError.map(URLError(.notConnectedToInternet), context: .read)
        let odd = BackendError.map(refused("XX000"), context: .read)

        guard case .network = lost as? TodAppError else {
            Issue.record("expected .network, got \(lost)")
            return
        }
        guard case .network = odd as? TodAppError else {
            Issue.record("expected .network, got \(odd)")
            return
        }
    }

    /// A request cancelled because the screen moved on is nobody's error.
    @Test
    func aCancellationStaysACancellation() {
        #expect(BackendError.map(URLError(.cancelled), context: .write) is CancellationError)
        #expect(BackendError.map(CancellationError(), context: .read) is CancellationError)
    }
}

@Suite
@MainActor
struct BackendErrorMessageTests {
    @Test
    func eachRefusalIsExplained() {
        #expect(PostSongModel.message(for: TodAppError.alreadyPosted)
            == "Du hast heute in dieser Gruppe schon einen Song gepostet.")
        #expect(PostSongModel.message(for: TodAppError.inviteInvalid)
            == "Diesen Code gibt es nicht, oder er ist abgelaufen.")
        #expect(PostSongModel.message(for: TodAppError.notAllowed)
            == "Das darfst du in dieser Gruppe nicht.")
        #expect(PostSongModel.message(for: TodAppError.roundClosed)
            == "Die Runde ist vorbei. Bewertet wird nur am selben Tag.")
        #expect(PostSongModel.message(for: TodAppError.notFound)
            == "Das gibt es nicht mehr. Zieh die Liste nach unten, um neu zu laden.")
    }

    @Test
    func theNewCasesEqualOnlyThemselves() {
        #expect(TodAppError.alreadyPosted == .alreadyPosted)
        #expect(TodAppError.inviteInvalid == .inviteInvalid)
        #expect(TodAppError.alreadyPosted != .inviteInvalid)
    }
}
