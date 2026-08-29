import Foundation

protocol BattleRepository: Sendable {
    func startBattle(_ battle: Battle, groupID: String) async throws
    func fetchActiveBattle(groupID: String) async throws -> Battle?
}
