import Foundation

protocol ChatRepository: Sendable {
    func sendMessage(_ message: ChatMessage, groupID: String) async throws
    func fetchMessages(groupID: String) async throws -> [ChatMessage]
    /// Says each time something new lands in the group -- a chat message, a
    /// post, a comment -- for as long as it is listened to, with what kind of
    /// row it was and who wrote it, so only what changed is read again
    /// (`GroupReload`).
    func groupActivity(groupID: String) -> AsyncStream<GroupActivity>
}

extension ChatRepository {
    /// A chat with no one else writing -- the local demo data. Stays open
    /// and silent until whoever listens stops.
    func groupActivity(groupID: String) -> AsyncStream<GroupActivity> {
        AsyncStream { _ in }
    }
}

/// One new row in a group, as the server announces it.
struct GroupActivity: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case chat, post, comment
    }

    let kind: Kind
    /// Who wrote the row, when the announcement says. Nil reads as someone
    /// else: reading once too often is harmless, missing a change is not.
    var authorID: String? = nil
}

/// What a burst of announcements needs read again. Each announcement used to
/// reload every group with its whole history -- in a busy chat, once per
/// message from anyone (the brief's audit, 8. Oktober, P1).
enum GroupReload: Equatable {
    case nothing
    /// Only the group's chat.
    case messages
    /// The one group: its posts and comments, and the chat with them.
    case group

    /// Own rows are skipped: whoever wrote them has read the group back
    /// already (`AppStore.sendMessage`, `addComment`, `post`), and the
    /// server's echo of them would only read it a second time.
    static func needed(for events: [GroupActivity], me: String) -> GroupReload {
        events
            .filter { $0.authorID != me }
            .reduce(.nothing) { needed, event in
                switch event.kind {
                case .chat: needed == .group ? .group : .messages
                case .post, .comment: .group
                }
            }
    }

    /// How long announcements are gathered before reading: a few messages in
    /// quick succession are read once, not once each.
    static let gathering: Duration = .milliseconds(300)
}
