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
    func addComment(
        _ text: String,
        authorID: String,
        authorName: String,
        submissionID: Int,
        groupID: String
    ) async throws {}
}

@Suite
@MainActor
struct AppStorePostingTests {
    /// Ids were minted from the posting group alone, so a post into a group
    /// numbered 1-4 produced 5 -- which the next group already used. Anything
    /// keyed on the id alone later (a share link, a notification, a networked
    /// repository) would then collide.
    @Test
    func aNewSubmissionIDDoesNotCollideWithAnotherGroup() async throws {
        func group(_ id: String, ids: [Int]) -> Group {
            Group(
                id: id, name: id, icon: "🧪", members: [], roundEndsAt: .now,
                submissions: ids.map {
                    Submission(id: $0, posterID: "x", track: "T", artist: "A",
                               coverColorHex: "#000000", comments: [])
                },
                board: [], chatMessages: [], activeBattle: nil
            )
        }
        let submissions = RecordingSubmissionRepository()
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group("a", ids: [1, 2, 3, 4]),
                                                    group("b", ids: [5, 6, 7])]),
            submissionRepo: submissions
        )
        await store.loadGroups()
        store.selectGroup("a")

        await store.post(candidate: TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: "abc",
                pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
            )
        ))

        let recorded = try #require(await submissions.submitted.first)
        #expect(recorded.id == 8)
    }

    /// The picked stretch has to survive the trip from the sheet into the
    /// submission, or dragging the handles was theatre.
    @Test
    func postingCarriesThePickedSection() async throws {
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

        await store.post(
            candidate: TrackCandidate(
                title: "Genesis", artist: "Justice",
                source: TrackSource(
                    service: .spotify, serviceTrackID: "abc",
                    pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
                )
            ),
            section: TrackSection(start: 82, end: 112)
        )

        let recorded = try #require(await submissions.submitted.first)
        #expect(recorded.section == TrackSection(start: 82, end: 112))
    }

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
                pageURL: URL(string: "https://open.spotify.com/track/abc")!,
                artworkURL: URL(string: "https://i.scdn.co/image/medium")
            )
        ))

        let recorded = try #require(await submissions.submitted.first)
        #expect(recorded.track == "Genesis")
        // The cover has to survive the trip, or every list falls back to a
        // flat colour for a track that has artwork.
        #expect(recorded.source?.artworkURL?.absoluteString == "https://i.scdn.co/image/medium")
        #expect(recorded.artist == "Justice")
        #expect(recorded.source?.serviceTrackID == "abc")
        #expect(recorded.source?.service == .spotify)
        // Nobody picked a section here, so none is invented.
        #expect(recorded.section == nil)
        #expect(store.lastError == nil)
    }
}
