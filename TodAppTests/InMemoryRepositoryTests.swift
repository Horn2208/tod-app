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
}
