import Foundation

protocol ChatRepository: Sendable {
    func sendMessage(_ message: ChatMessage, groupID: String) async throws
    func fetchMessages(groupID: String) async throws -> [ChatMessage]
}
