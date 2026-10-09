import Foundation
import Testing
@testable import TodApp

/// The small things of round 4 (`docs/prompt.md`, item 24).
@Suite
@MainActor
struct PolishTests {
    @Test
    func aConnectionFailureCanBeTriedAgain() async {
        let store = AppStore(groupRepo: FlakyGroupRepository())

        await store.loadGroups()
        #expect(store.canRetry)
        #expect(!store.hasLoadedGroups)

        await store.retryLast()

        #expect(!store.canRetry)
        #expect(store.hasLoadedGroups)
    }

    @Test
    func aRefusalIsNotOfferedAgain() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, submissionRepo: repo, voteRepo: repo, chatRepo: repo,
                             battleRepo: repo, profileRepo: repo, moderationRepo: repo)
        await store.loadGroups()
        let theirs = try #require(store.groups.first { $0.creatorID != "du" })

        _ = await store.deleteGroup(theirs.id)

        #expect(store.lastError == .notAllowed)
        #expect(!store.canRetry)
    }

    @Test
    func someoneWhoLeftIsNamedAsSuchNotByTheirID() async {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, submissionRepo: repo, voteRepo: repo, chatRepo: repo,
                             battleRepo: repo, profileRepo: repo, moderationRepo: repo)
        await store.loadGroups()

        #expect(store.voterName("8f14e45f-ceea-467a-9575-1c6f0a6b0e2a") == "Ehemaliges Mitglied")
        #expect(store.voterName("du") == "Du")
    }
}
