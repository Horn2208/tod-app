import Foundation

protocol ChatRepository: Sendable {
    func sendMessage(_ message: ChatMessage, groupID: String) async throws
    func fetchMessages(groupID: String) async throws -> [ChatMessage]
    /// Says each time someone writes in the group, for as long as it is
    /// listened to. The messages themselves come from reading the group again.
    func newMessages(groupID: String) -> AsyncStream<Void>
}

extension ChatRepository {
    /// A chat with no one else writing -- the local demo data. Stays open
    /// and silent until whoever listens stops.
    func newMessages(groupID: String) -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}
