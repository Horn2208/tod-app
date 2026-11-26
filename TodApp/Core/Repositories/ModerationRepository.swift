import Foundation

/// Reporting and blocking, as App Review asks of apps where people post for
/// each other (Guideline 1.2). A report lands where whoever runs the project
/// reads it; a block hides one person's posts, comments and messages from
/// the one who blocked them, nobody else.
protocol ModerationRepository: Sendable {
    func report(_ report: Report) async throws
    func block(_ userID: String) async throws
    func unblock(_ userID: String) async throws
    /// Whom the signed-in person has blocked.
    func fetchBlockedIDs() async throws -> Set<String>
}

enum ReportReason: String, CaseIterable, Sendable {
    case offensive, spam, inappropriate, other

    var label: String {
        switch self {
        case .offensive: "Beleidigend"
        case .spam: "Spam"
        case .inappropriate: "Unangemessen"
        case .other: "Etwas anderes"
        }
    }
}

struct Report: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case submission(Int)
        case comment(Int)
        case chatMessage(UUID)
        case member(String)

        /// As the `reports` table spells it.
        var kind: String {
            switch self {
            case .submission: "submission"
            case .comment: "comment"
            case .chatMessage: "chat_message"
            case .member: "member"
            }
        }

        var id: String {
            switch self {
            case .submission(let id), .comment(let id): String(id)
            case .chatMessage(let id): id.uuidString.lowercased()
            case .member(let id): id
            }
        }
    }

    let groupID: String
    let target: Target
    /// Who wrote what is reported -- or who is, for a person.
    let reportedUserID: String?
    let reason: ReportReason
    /// What it said, kept with the report: the post may be gone by the time
    /// anyone reads it.
    let excerpt: String?

    static let maximumExcerptLength = 500

    init(groupID: String, target: Target, reportedUserID: String?, reason: ReportReason, excerpt: String?) {
        self.groupID = groupID
        self.target = target
        self.reportedUserID = reportedUserID
        self.reason = reason
        self.excerpt = excerpt.map { String($0.prefix(Self.maximumExcerptLength)) }
    }
}
