import Foundation
import Testing
@testable import TodApp

struct MockGroupRepository: GroupRepository {
    var groups: [Group]
    func fetchGroups() async throws -> [Group] { groups }
    func fetchGroup(id: String) async throws -> Group {
        guard let group = groups.first(where: { $0.id == id }) else { throw TodAppError.notFound }
        return group
    }
}

@Suite
@MainActor
struct AppStoreTests {
    @Test
    func loadGroupsPopulatesStateFromRepository() async {
        let group = Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], board: [], chatMessages: [], activeBattle: nil
        )
        let store = AppStore(groupRepo: MockGroupRepository(groups: [group]))

        await store.loadGroups()

        #expect(store.groups.map(\.id) == ["test"])
    }
}

/// Records what the store handed over, so the test can assert the source
/// survived the trip instead of just checking that nothing blew up.
actor RecordingSubmissionRepository: SubmissionRepository {
    private(set) var submitted: [Submission] = []
    func submit(_ submission: Submission, to groupID: String) async throws {
        submitted.append(submission)
    }
    func addComment(_ text: String, submissionID: Int, groupID: String) async throws {}
}

@Suite
@MainActor
struct AppStorePostingTests {
    @Test
    func postingACandidateStoresItsSource() async throws {
        let group = Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], board: [], chatMessages: [], activeBattle: nil
        )
        let submissions = RecordingSubmissionRepository()
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group]),
            submissionRepo: submissions
        )
        await store.loadGroups()
        store.selectGroup("test")

        await store.post(candidate: TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: "abc",
                pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
            )
        ))

        let recorded = try #require(await submissions.submitted.first)
        #expect(recorded.track == "Genesis")
        #expect(recorded.artist == "Justice")
        #expect(recorded.source?.serviceTrackID == "abc")
        #expect(recorded.source?.service == .spotify)
        #expect(store.lastError == nil)
    }
}
