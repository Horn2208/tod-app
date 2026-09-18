import Foundation
import Supabase

/// What the app writes, one body per kind of write, in the database's
/// spelling. Only the columns `authenticated` is granted: ids, authors, times
/// and a post's day are the server's to set. A nil optional is left out of
/// the body -- except where leaving it out would keep an old value.

extension BackendRecords {
    /// The encoder the library itself uses.
    static let encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder

    /// Cuts a string to what a `char_length` check allows. Postgres counts
    /// Unicode scalars, so the cut is made in those.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.prefix(limit))
        return String(scalars)
    }
}

struct NewSubmissionPayload: Encodable, Sendable {
    static let unknownArtist = "Unbekannt"
    /// `submissions.track` and `.artist`.
    static let maximumLength = 200

    let groupID: String
    let track: String
    let artist: String
    let service: String?
    let serviceTrackID: String?
    let pageURL: String?
    let artworkURL: String?
    let isrc: String?
    let appleMusicID: String?
    let sectionStart: Double?
    let sectionEnd: Double?

    init(submission: Submission, groupID: String) {
        self.groupID = groupID
        track = BackendRecords.clipped(submission.track, to: Self.maximumLength)
        let artist = submission.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        // A pasted link whose details could not be read has no artist, and
        // the database wants one.
        self.artist = BackendRecords.clipped(artist.isEmpty ? Self.unknownArtist : artist, to: Self.maximumLength)
        service = submission.source?.service.rawValue
        serviceTrackID = submission.source?.serviceTrackID
        pageURL = submission.source?.pageURL.absoluteString
        artworkURL = submission.source?.artworkURL?.absoluteString
        isrc = submission.isrc
        appleMusicID = submission.appleMusicID
        sectionStart = submission.section?.start
        sectionEnd = submission.section?.end
    }

    private enum CodingKeys: String, CodingKey {
        case track, artist, service, isrc
        case groupID = "group_id"
        case serviceTrackID = "service_track_id"
        case pageURL = "page_url"
        case artworkURL = "artwork_url"
        case appleMusicID = "apple_music_id"
        case sectionStart = "section_start"
        case sectionEnd = "section_end"
    }
}

struct NewGroupPayload: Encodable, Sendable {
    let name: String
    let icon: String
}

/// A group's editable columns, each only when it changes.
struct GroupPatch: Encodable, Sendable {
    let name: String?
    let invitePolicy: InvitePolicy?
    let imagePath: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case invitePolicy = "invite_policy"
        case imagePath = "image_path"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(
            invitePolicy.map { $0 == .creatorOnly ? "creator_only" : "everyone" }, forKey: .invitePolicy)
        try c.encodeIfPresent(imagePath, forKey: .imagePath)
    }
}

struct NewInvitePayload: Encodable, Sendable {
    let groupID: String

    private enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
    }
}

/// `group_invites`, as a new one comes back.
struct InviteRecord: Decodable, Sendable {
    let invite: GroupInvite

    private enum CodingKeys: String, CodingKey {
        case code
        case groupID = "group_id"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invite = GroupInvite(
            code: try c.decode(String.self, forKey: .code),
            groupID: try c.decode(String.self, forKey: .groupID).lowercased(),
            expiresAt: try c.decode(Date.self, forKey: .expiresAt))
    }
}

struct NewVotePayload: Encodable, Sendable {
    let submissionID: Int
    let groupID: String
    let roundDay: String
    let rating: Int
    let note: String?

    /// `votes.note`.
    static let maximumNoteLength = 280

    init(vote: Vote, groupID: String, roundDay: String) {
        submissionID = vote.submissionID
        self.groupID = groupID
        self.roundDay = roundDay
        rating = vote.rating.rawValue
        note = vote.note.map { BackendRecords.clipped($0, to: Self.maximumNoteLength) }
    }

    private enum CodingKeys: String, CodingKey {
        case rating, note
        case submissionID = "submission_id"
        case groupID = "group_id"
        case roundDay = "round_day"
    }
}

/// A changed rating. The note is always written, null included: a new
/// rating without a reason must not keep the old reason.
struct VotePatch: Encodable, Sendable {
    let rating: Int
    let note: String?

    init(rating: Int, note: String?) {
        self.rating = rating
        self.note = note.map { BackendRecords.clipped($0, to: NewVotePayload.maximumNoteLength) }
    }

    private enum CodingKeys: String, CodingKey {
        case rating, note
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rating, forKey: .rating)
        try c.encode(note, forKey: .note)
    }
}

struct NewGemPayload: Encodable, Sendable {
    let groupID: String
    let roundDay: String
    let submissionID: Int

    private enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case roundDay = "round_day"
        case submissionID = "submission_id"
    }
}

struct GemPatch: Encodable, Sendable {
    let submissionID: Int

    private enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
    }
}

struct NewCommentPayload: Encodable, Sendable {
    /// `comments.body`.
    static let maximumLength = 1000

    let submissionID: Int
    let groupID: String
    let body: String

    init(submissionID: Int, groupID: String, body: String) {
        self.submissionID = submissionID
        self.groupID = groupID
        self.body = BackendRecords.clipped(body, to: Self.maximumLength)
    }

    private enum CodingKeys: String, CodingKey {
        case body
        case submissionID = "submission_id"
        case groupID = "group_id"
    }
}

struct NewChatPayload: Encodable, Sendable {
    let id: String
    let groupID: String
    let body: String
    let mentionedSubmissionID: Int?

    /// `chat_messages.body`.
    static let maximumLength = 2000

    init(message: ChatMessage, groupID: String) {
        id = message.id.uuidString.lowercased()
        self.groupID = groupID
        body = BackendRecords.clipped(message.text, to: Self.maximumLength)
        mentionedSubmissionID = message.mentionedSubmissionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, body
        case groupID = "group_id"
        case mentionedSubmissionID = "mentioned_submission_id"
    }
}

struct ProfilePatch: Encodable, Sendable {
    let name: String?
    let avatarPath: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case avatarPath = "avatar_path"
    }
}
