import Foundation
import Testing
@testable import TodApp

@Suite
struct InMemoryRepositoryTests {
    /// Pins the fix for a successful post never registering: `TodayView`
    /// gates on `!me.hasPostedToday`, which was only ever set by the seed
    /// literals -- so after a real `submit(_:to:)` the poster stayed stuck on
    /// "not posted yet" and could post again into the same round.
    @Test
    func submitMarksThePosterAsHavingPostedTodayWithoutTouchingOtherMembers() async throws {
        // A fresh instance, not `.shared` -- this test must not depend on, or
        // leak into, any other test's view of the singleton.
        let repo = InMemoryRepository()
        let before = try await repo.fetchGroup(id: "lnc")
        // "sude" is seeded with hasPostedToday == false, so this exercises a
        // real flip rather than starting from an already-true value.
        #expect(before.members.first(where: { $0.id == "sude" })?.hasPostedToday == false)

        let submission = Submission(
            id: 999, posterID: "sude", track: "Test Track", artist: "Test Artist",
            coverColorHex: "#000000", comments: [], source: nil
        )
        try await repo.submit(submission, to: "lnc")

        let after = try await repo.fetchGroup(id: "lnc")
        #expect(after.members.first(where: { $0.id == "sude" })?.hasPostedToday == true)

        // No other member's flag may move as a side effect of this submission.
        for member in after.members where member.id != "sude" {
            let wasBefore = before.members.first(where: { $0.id == member.id })?.hasPostedToday
            #expect(member.hasPostedToday == wasBefore)
        }
    }

    /// Votes were filed under one flat key, `"<voter>-<submission>-<group>"`,
    /// and read back with `hasSuffix("-<group>")`. Any group id ending in
    /// `-lnc` therefore matched group `lnc` as well, so one round's ratings and
    /// hidden gems showed up inside another's. The key is three separate fields
    /// now; this pins the scoping that bought.
    ///
    /// It no longer uses the colliding ids that gave the bug its name. A vote
    /// has to name a submission that really is in that group now, so a group
    /// invented to be a suffix of another cannot take one -- and the sibling
    /// test that voted as `du-side` into `side-lnc` went with it rather than
    /// being propped up with groups the repository would refuse.
    @Test
    func votesDoNotLeakBetweenGroups() async throws {
        let repo = InMemoryRepository()

        try await repo.castVote(
            Vote(voterID: "du", submissionID: 5, rating: .banger, isHiddenGem: false),
            groupID: "wg")
        try await repo.setHiddenGem(submissionID: 5, voterID: "du", groupID: "wg")

        let mine = try await repo.fetchMyVotes(voterID: "du", groupID: "lnc", day: Date())
        #expect(mine.ratings.isEmpty)
        #expect(mine.hiddenGemID == nil)

        let scores = try await repo.fetchRoundScores(groupID: "lnc", day: Date())
        #expect(scores.allSatisfy { $0.points == 0 })
        #expect(scores.allSatisfy { $0.hiddenGemCount == 0 })
    }
}
