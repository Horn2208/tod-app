import Foundation

/// A code to pass on to a friend, who joins the group with it. With real
/// accounts nobody can be added by name -- there is no one behind a typed
/// name -- so a group grows by people letting themselves in.
struct GroupInvite: Equatable, Sendable {
    let code: String
    let groupID: String
    let expiresAt: Date

    /// How long a code works. The database's default says the same.
    static let lifetime: TimeInterval = 7 * 24 * 3600
}

/// How a code is read, whatever way it arrived.
enum InviteCode {
    /// Eight random bytes, written as hex (`group_invites.code`).
    static let length = 16

    /// The code without the blocks it is shown in, the spaces a paste brings
    /// along, or capitals. Anything else is kept, so a typo stays a typo.
    static func normalized(_ raw: String) -> String {
        String(raw.lowercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    /// Worth sending to the server at all.
    static func isPlausible(_ raw: String) -> Bool {
        let code = normalized(raw)
        return code.count == length && code.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// In blocks of four, to be read out or copied by eye.
    static func display(_ code: String) -> String {
        var blocks: [Substring] = []
        var rest = Substring(normalized(code))
        while !rest.isEmpty {
            blocks.append(rest.prefix(4))
            rest = rest.dropFirst(4)
        }
        return blocks.joined(separator: "-")
    }

    /// What goes out when a code is shared. There is no link to tap, so it
    /// says where the code goes.
    static func message(groupName: String, code: String) -> String {
        "Komm in meine Gruppe „\(groupName)“ bei TodApp. "
            + "Unter Gruppen → + → Mit Code beitreten eingeben: \(display(code))"
    }

    /// A fresh code, for the data kept in memory.
    static func random() -> String {
        (0..<length).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined()
    }
}

/// What a new group may be called and wear, by the database's rules.
enum NewGroupDraft {
    static let defaultIcon = "🎵"
    /// `groups.name` is 1 to 40 characters, counted the way Postgres counts:
    /// Unicode scalars, not what the eye sees as one character.
    static let maximumNameLength = 40
    static let maximumIconLength = 16
    /// The signs offered as a grid; anything else goes in through "Anderes …".
    static let iconChoices = [
        "🎵", "🎧", "🎸", "🎤", "🥁", "🎹", "🎷", "💿",
        "🔥", "✨", "🌙", "🌊", "🏠", "🍕", "⚡️", "🪩",
    ]

    static func name(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maximumNameLength else { return nil }
        return trimmed
    }

    /// One character -- usually an emoji -- or the note.
    static func icon(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, String(first).unicodeScalars.count <= maximumIconLength
        else { return defaultIcon }
        return String(first)
    }
}
