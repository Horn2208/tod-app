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
        private var continuation: AsyncStream<GroupActivity>.Continuation?

        func sendMessage(_ message: ChatMessage, groupID: String) async throws {
            try await base.sendMessage(message, groupID: groupID)
        }

        func fetchMessages(groupID: String) async throws -> [ChatMessage] {
            try await base.fetchMessages(groupID: groupID)
        }

        func groupActivity(groupID: String) -> AsyncStream<GroupActivity> {
            AsyncStream { self.continuation = $0 }
        }

        func someoneWrote(_ kind: GroupActivity.Kind = .chat) {
            continuation?.yield(GroupActivity(kind: kind, authorID: "someone-else"))
        }
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

        let following = Task { await store.followGroup() }
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

    /// Not only chat: a song someone else posts shows up the same way.
    @Test(.timeLimit(.minutes(1)))
    func aPostFromSomeoneElseAppearsWithoutPulling() async throws {
        let chat = LiveChat()
        let repo = chat.base
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: chat, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
        await store.loadGroups()
        let groupID = try #require(store.currentGroup?.id)

        let following = Task { await store.followGroup() }
        #expect(await waitUntil { chat.isListening })

        let before = store.currentGroup?.submissions.count ?? 0
        let post = Submission(
            id: 9_999, posterID: "someone-new", track: "Nights", artist: "Frank Ocean",
            coverColorHex: "#222222", comments: [])
        try await repo.submit(post, to: groupID)
        chat.someoneWrote(.post)

        #expect(await waitUntil { (store.currentGroup?.submissions.count ?? 0) == before + 1 })
        following.cancel()
    }

}

/// What a burst of announcements has read again.
@Suite
struct GroupReloadTests {
    private let me = "me"

    @Test
    func aMessageFromSomeoneElseReadsOnlyTheChat() {
        #expect(GroupReload.needed(for: [GroupActivity(kind: .chat, authorID: "lena")], me: me) == .messages)
    }

    @Test
    func aPostOrACommentReadsTheGroup() {
        #expect(GroupReload.needed(for: [GroupActivity(kind: .post, authorID: "lena")], me: me) == .group)
        #expect(GroupReload.needed(for: [GroupActivity(kind: .comment, authorID: "lena")], me: me) == .group)
    }

    /// Several at once are read once, and the group covers the chat.
    @Test
    func aBurstIsReadOnceAndTheGroupCoversTheChat() {
        let burst = [
            GroupActivity(kind: .chat, authorID: "lena"),
            GroupActivity(kind: .comment, authorID: "max"),
            GroupActivity(kind: .chat, authorID: "lena"),
        ]
        #expect(GroupReload.needed(for: burst, me: me) == .group)
    }

    /// One's own rows come back from the server too; whoever wrote them has
    /// read the group already.
    @Test
    func ownRowsAreNotReadTwice() {
        #expect(GroupReload.needed(for: [GroupActivity(kind: .chat, authorID: me)], me: me) == .nothing)
        #expect(GroupReload.needed(
            for: [GroupActivity(kind: .chat, authorID: me), GroupActivity(kind: .chat, authorID: "lena")],
            me: me) == .messages)
    }

    /// An announcement that does not say who wrote it is read, to be safe.
    @Test
    func anUnknownAuthorIsRead() {
        #expect(GroupReload.needed(for: [GroupActivity(kind: .chat)], me: me) == .messages)
    }
}
