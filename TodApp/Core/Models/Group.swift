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

// MARK: - Leaving, removing, deleting

extension GroupPermissions {
    /// Only the creator removes someone, and never themselves -- leaving is
    /// its own button. The same rule the server's row level security holds.
    static func mayRemove(_ memberID: String, from group: Group, asking userID: String) -> Bool {
        userID == group.creatorID
            && memberID != userID
            && group.members.contains { $0.id == memberID }
    }

    /// Only the creator deletes a group, for everyone in it.
    static func mayDelete(_ group: Group, asking userID: String) -> Bool {
        userID == group.creatorID
    }

    /// What leaving does.
    enum Leaving: Equatable {
        /// Out of the group; it carries on for the others.
        case leave
        /// The last one out turns the light off: a group nobody is in would
        /// only sit in the database.
        case deleteGroup
    }

    /// The group goes with its last member -- when that member is the one
    /// who may delete it. Anyone else who is last simply leaves; the server
    /// would refuse them the delete.
    static func leaving(_ group: Group, asking userID: String) -> Leaving {
        let others = group.members.contains { $0.id != userID }
        return !others && mayDelete(group, asking: userID) ? .deleteGroup : .leave
    }
}

/// What someone may take back of their own. Mirrors the server's delete
/// policies (`submissions_delete_own_today`, `comments_delete_own`,
/// `chat_messages_delete_own`), so the app offers only what it will be
/// allowed.
enum OwnContent {
    /// One's own post, while its round still runs -- a song already rated
    /// and revealed stays, or yesterday's scores would change.
    static func mayDelete(
        _ submission: Submission, asking userID: String, now: Date,
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> Bool {
        submission.posterID == userID && calendar.isDate(submission.postedAt, inSameDayAs: now)
    }

    static func mayDelete(_ comment: Comment, asking userID: String) -> Bool {
        comment.authorID == userID
    }

    /// The demo data has no author ids; there "from the current user" is
    /// what says whose a message is.
    static func mayDelete(_ message: ChatMessage, asking userID: String) -> Bool {
        if let authorID = message.authorID { return authorID == userID }
        return message.isFromCurrentUser
    }
}
