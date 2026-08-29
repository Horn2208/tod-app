import Foundation

protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [Group]
    func fetchGroup(id: String) async throws -> Group
}
