import Foundation

protocol LeaderboardRepository: Sendable {
    func fetchBoard(groupID: String) async throws -> [BoardEntry]
}
