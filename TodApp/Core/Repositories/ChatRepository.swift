import Foundation

protocol ChatRepository: Sendable {
    func sendMessage(_ message: ChatMessage, groupID: String) async throws
    func fetchMessages(groupID: String) async throws -> [ChatMessage]
    /// Says each time something new lands in the group -- a chat message, a
    /// post, a comment -- for as long as it is listened to. What it is comes
    /// from reading the group again.
    func groupActivity(groupID: String) -> AsyncStream<Void>
}

extension ChatRepository {
    /// A chat with no one else writing -- the local demo data. Stays open
    /// and silent until whoever listens stops.
    func groupActivity(groupID: String) -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}
