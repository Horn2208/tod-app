import Foundation

/// The last chat message seen per group, on this phone, for the dot in the
/// groups list (`GroupsFeed.hasUnread`). `GroupRow` reads the same key through
/// `@AppStorage`, so the dot goes as soon as the chat has been open.
enum ChatReadMarks {
    static func key(for groupID: String) -> String {
        "chat.lastSeen.\(groupID)"
    }

    static func markSeen(_ messageID: UUID, in groupID: String, defaults: UserDefaults = .standard) {
        defaults.set(messageID.uuidString, forKey: key(for: groupID))
    }

    static func lastSeen(in groupID: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(for: groupID))
    }
}
