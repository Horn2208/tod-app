import Foundation
import Testing
@testable import TodApp

/// Rounds follow Berlin's day, as the database does, wherever the phone is:
/// a phone in London counted 23:30 as "today" while the server had moved on
/// (the brief's second audit, A2).
@Suite
struct BerlinRoundTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// 00:30 in Berlin on 8 October is still 23:30 on 7 October in London.
    private var justAfterBerlinMidnight: Date { date("2026-10-07T22:30:00Z") }

    private func post(at iso: String) -> Submission {
        Submission(
            id: 1, posterID: "lena", track: "Nights", artist: "Frank Ocean",
            coverColorHex: "#222222", comments: [], postedAt: date(iso))
    }

    /// Posted at 23:00 Berlin on the 7th: by 00:30 Berlin it is yesterday's
    /// round, revealed -- not today's, as a London calendar would say.
    @Test
    func aPostFromBeforeBerlinMidnightIsYesterdaysRound() {
        let song = post(at: "2026-10-07T21:00:00Z")
        #expect(RoundVisibility.runningSubmissions(from: [song], today: justAfterBerlinMidnight).isEmpty)
        #expect(RoundVisibility.revealedSubmissions(from: [song], today: justAfterBerlinMidnight).map(\.id) == [1])
        #expect(!RoundVisibility.isVotable(roundDay: song.postedAt, today: justAfterBerlinMidnight))
    }

    /// The same moment on a London calendar, to show what the default fixes.
    @Test
    func aLondonCalendarWouldStillCallItToday() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let song = post(at: "2026-10-07T21:00:00Z")
        #expect(RoundVisibility.isVotable(roundDay: song.postedAt, today: justAfterBerlinMidnight, calendar: london))
    }

    /// The day the reveal asks the server for is Berlin's yesterday.
    @Test
    func theRevealedDayIsBerlinsYesterday() {
        #expect(RoundDay.berlin(RoundVisibility.revealedDay(today: justAfterBerlinMidnight)) == "2026-10-07")
    }
}

/// Midnight with the app open: the next turn, and a rating that came too late.
@MainActor
@Suite
struct RoundTurnTests {
    @Test
    func theNextTurnIsBerlinsNextMidnight() {
        let afternoon = ISO8601DateFormatter().date(from: "2026-10-08T13:00:00Z")!
        #expect(AppStore.nextRoundTurn(after: afternoon) == ISO8601DateFormatter().date(from: "2026-10-08T22:00:00Z")!)
    }

    /// Rating a song whose day is over says so, instead of doing nothing.
    @Test
    func aRatingAfterMidnightSaysTheRoundIsOver() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
        await store.loadGroups()
        let yesterdays = try #require(store.revealedSubmissions.first { $0.posterID != store.profile.id })

        await store.castVote(.good, for: yesterdays.id)

        #expect(store.roundIsOver)
        store.acknowledgeRoundOver()
        #expect(!store.roundIsOver)
    }
}

/// A rating shows at once and goes back if the server refuses it.
@MainActor
@Suite
struct OptimisticVoteTests {
    /// Refuses every vote and gem; reads come from the in-memory data.
    final class RefusingVotes: VoteRepository, @unchecked Sendable {
        let base: InMemoryRepository
        init(base: InMemoryRepository) { self.base = base }
        func castVote(_ vote: Vote, groupID: String) async throws { throw TodAppError.notAllowed }
        func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
            throw TodAppError.notAllowed
        }
        func fetchMyVotes(voterID: String, groupID: String, day: Date) async throws -> MyVotes {
            try await base.fetchMyVotes(voterID: voterID, groupID: groupID, day: day)
        }
        func fetchRoundScores(groupID: String, day: Date) async throws -> [RoundScore] {
            try await base.fetchRoundScores(groupID: groupID, day: day)
        }
        func fetchVotes(groupID: String, day: Date) async throws -> [Vote] {
            try await base.fetchVotes(groupID: groupID, day: day)
        }
        func fetchRevealedScores(groupID: String) async throws -> [RoundScore] {
            try await base.fetchRevealedScores(groupID: groupID)
        }
    }

    private func store(votes: any VoteRepository, repo: InMemoryRepository) -> AppStore {
        AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: votes,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
    }

    @Test
    func anAcceptedRatingStays() async throws {
        let repo = InMemoryRepository()
        let store = store(votes: repo, repo: repo)
        await store.loadGroups()
        let song = try #require(store.votableSubmissions.first)

        await store.castVote(.banger, for: song.id)

        #expect(store.myVotes.ratings[song.id] == .banger)
    }

    @Test
    func aRefusedRatingGoesBack() async throws {
        let repo = InMemoryRepository()
        let store = store(votes: RefusingVotes(base: repo), repo: repo)
        await store.loadGroups()
        let song = try #require(store.votableSubmissions.first)

        await store.castVote(.banger, for: song.id)

        #expect(store.myVotes.ratings[song.id] == nil)
        #expect(store.lastError == .notAllowed)
    }

    @Test
    func aRefusedGemGoesBack() async throws {
        let repo = InMemoryRepository()
        let store = store(votes: RefusingVotes(base: repo), repo: repo)
        await store.loadGroups()
        let song = try #require(store.votableSubmissions.first)

        await store.toggleHiddenGem(song.id)

        #expect(store.myVotes.hiddenGemID == nil)
    }
}
