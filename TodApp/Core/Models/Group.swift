import Foundation

/// Who may bring someone new into a group.
///
/// The policy itself is the creator's to change. Letting everyone change it
/// would make it no rule at all: anyone locked out could unlock themselves.
enum InvitePolicy: String, Codable, CaseIterable {
    case everyone, creatorOnly

    var label: String {
        switch self {
        case .everyone: "Alle Mitglieder"
        case .creatorOnly: "Nur wer die Gruppe erstellt hat"
        }
    }
}

struct Group: Identifiable, Codable {
    let id: String
    var name: String
    var icon: String
    /// A real picture for the group. `icon` stays as the fallback, so a group
    /// without one still shows something rather than a grey square. Defaulted
    /// to `nil` so every existing construction site -- none of which has a
    /// picture to supply -- keeps compiling.
    var imageData: Data? = nil
    var members: [Member]
    var roundEndsAt: Date
    var submissions: [Submission]
    var chatMessages: [ChatMessage]
    var activeBattle: Battle?
    /// Who made this group. Needed the moment a permission depends on it --
    /// `Member` says who is in a group, never who started it.
    var creatorID: String = "du"
    var invitePolicy: InvitePolicy = .everyone
}

/// The rules that depend on who someone is in a group, kept out of the views
/// so they can be checked on their own -- the same way `RoundVisibility` and
/// `Streak` are.
enum GroupPermissions {
    static func mayInvite(_ userID: String, to group: Group) -> Bool {
        switch group.invitePolicy {
        case .everyone: group.members.contains { $0.id == userID }
        case .creatorOnly: userID == group.creatorID
        }
    }

    /// Only the creator moves this lever. See `InvitePolicy`.
    static func mayChangeInvitePolicy(_ userID: String, of group: Group) -> Bool {
        userID == group.creatorID
    }
}
