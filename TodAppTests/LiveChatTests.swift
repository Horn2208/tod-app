import Foundation
import Testing
@testable import TodApp

/// A chat that hears of new messages: the server says a row went in, and the
/// open chat reads the group again.
@MainActor
@Suite
struct LiveChatTests {
    /// Chat from the in-memory store, plus a switch the test flips to say
    /// "someone wrote".
    final class LiveChat: ChatRepository, @unchecked Sendable {
        let base = InMemoryRepository()
        private var continuation: AsyncStream<Void>.Continuation?

        func sendMessage(_ message: ChatMessage, groupID: String) async throws {
            try await base.sendMessage(message, groupID: groupID)
        }

        func fetchMessages(groupID: String) async throws -> [ChatMessage] {
            try await base.fetchMessages(groupID: groupID)
        }

        func newMessages(groupID: String) -> AsyncStream<Void> {
            AsyncStream { self.continuation = $0 }
        }

        func someoneWrote() { continuation?.yield() }
        var isListening: Bool { continuation != nil }
    }

    @Test(.timeLimit(.minutes(1)))
    func aMessageFromSomeoneElseAppearsWithoutPulling() async throws {
        let chat = LiveChat()
        let repo = chat.base
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: chat, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
        await store.loadGroups()
        let groupID = try #require(store.currentGroup?.id)

        let following = Task { await store.followChat() }
        #expect(await waitUntil { chat.isListening })

        let message = ChatMessage(
            id: UUID(), authorTag: "LE", authorName: "Lena", text: "hört ihr das auch?",
            isFromCurrentUser: false)
        try await repo.sendMessage(message, groupID: groupID)
        chat.someoneWrote()

        #expect(await waitUntil {
            store.currentGroup?.chatMessages.contains { $0.id == message.id } == true
        })
        following.cancel()
    }
}
