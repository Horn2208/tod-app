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
