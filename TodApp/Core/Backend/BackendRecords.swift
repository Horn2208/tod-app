import Foundation
import Supabase

/// Records as the Supabase project sends them, one type per table, named after
/// the columns the app selects. Kept apart from the app's models: the tables
/// store what cannot be derived, the models carry what the screens need, and
/// `GroupAssembly` is where one becomes the other.
///
/// Every uuid is read in lower case. Postgres writes them that way, and the
/// app compares ids as strings -- an upper-case copy from anywhere would make
/// the signed-in user a stranger in their own group.
enum BackendRecords {
    /// The decoder the library itself uses, so a row decodes here exactly as
    /// it does off the wire -- timestamps with microseconds and an offset.
    static let decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
}

private extension KeyedDecodingContainer {
    func decodeID(_ key: Key) throws -> String {
        try decode(String.self, forKey: key).lowercased()
    }

    func decodeIDIfPresent(_ key: Key) throws -> String? {
        try decodeIfPresent(String.self, forKey: key)?.lowercased()
    }
}

/// `groups`, with its members embedded (`group_members(user_id, profiles(…))`).
struct GroupRecord: Decodable, Sendable {
    let id: String
    let name: String
    let icon: String
    let imagePath: String?
    /// Nil once the creator's account is gone; the group stays everyone's.
    let creatorID: String?
    let invitePolicy: String
    let members: [MemberRecord]

    init(
        id: String, name: String, icon: String, imagePath: String?, creatorID: String?,
        invitePolicy: String, members: [MemberRecord]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.imagePath = imagePath
        self.creatorID = creatorID
        self.invitePolicy = invitePolicy
        self.members = members
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon
        case imagePath = "image_path"
        case creatorID = "creator_id"
        case invitePolicy = "invite_policy"
        case members = "group_members"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeID(.id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        creatorID = try c.decodeIDIfPresent(.creatorID)
        invitePolicy = try c.decode(String.self, forKey: .invitePolicy)
        members = try c.decodeIfPresent([MemberRecord].self, forKey: .members) ?? []
    }
}

/// One `group_members` row with the member's profile embedded. The profile is
/// null when the server does not show it.
struct MemberRecord: Decodable, Sendable {
    let userID: String
    let profile: ProfileRecord?

    init(userID: String, profile: ProfileRecord?) {
        self.userID = userID
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case profile = "profiles"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeID(.userID)
        profile = try c.decodeIfPresent(ProfileRecord.self, forKey: .profile)
    }
}

/// `profiles`. Embedded under a member it carries no id and no premium flag,
/// so both are optional here.
struct ProfileRecord: Decodable, Sendable, Equatable {
    let id: String?
    let name: String
    let avatarPath: String?
    let isPremium: Bool?

    init(id: String?, name: String, avatarPath: String?, isPremium: Bool?) {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
        self.isPremium = isPremium
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case avatarPath = "avatar_path"
        case isPremium = "is_premium"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIDIfPresent(.id)
        name = try c.decode(String.self, forKey: .name)
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium)
    }
}

/// `submissions`, optionally with its comments embedded.
struct SubmissionRecord: Decodable, Sendable {
    let id: Int
    let groupID: String
    let posterID: String
    let track: String
    let artist: String
    let service: String?
    let serviceTrackID: String?
    let pageURL: String?
    let artworkURL: String?
    let durationSeconds: Int?
    let isrc: String?
    let appleMusicID: String?
    let sectionStart: Double?
    let sectionEnd: Double?
    let postedAt: Date
    /// The round's day as the database worked it out, `yyyy-MM-dd`.
    let roundDay: String
    let comments: [CommentRecord]?

    init(
        id: Int, groupID: String, posterID: String, track: String, artist: String,
        service: String?, serviceTrackID: String?, pageURL: String?, artworkURL: String?,
        durationSeconds: Int?, isrc: String?, appleMusicID: String?,
        sectionStart: Double?, sectionEnd: Double?, postedAt: Date, roundDay: String,
        comments: [CommentRecord]?
    ) {
        self.id = id
        self.groupID = groupID
        self.posterID = posterID
        self.track = track
        self.artist = artist
        self.service = service
        self.serviceTrackID = serviceTrackID
        self.pageURL = pageURL
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
        self.isrc = isrc
        self.appleMusicID = appleMusicID
        self.sectionStart = sectionStart
        self.sectionEnd = sectionEnd
        self.postedAt = postedAt
        self.roundDay = roundDay
        self.comments = comments
    }

    private enum CodingKeys: String, CodingKey {
        case id, track, artist, service, isrc, comments
        case groupID = "group_id"
        case posterID = "poster_id"
        case serviceTrackID = "service_track_id"
        case pageURL = "page_url"
        case artworkURL = "artwork_url"
        case durationSeconds = "duration_seconds"
        case appleMusicID = "apple_music_id"
        case sectionStart = "section_start"
        case sectionEnd = "section_end"
        case postedAt = "posted_at"
        case roundDay = "round_day"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        groupID = try c.decodeID(.groupID)
        posterID = try c.decodeID(.posterID)
        track = try c.decode(String.self, forKey: .track)
        artist = try c.decode(String.self, forKey: .artist)
        service = try c.decodeIfPresent(String.self, forKey: .service)
        serviceTrackID = try c.decodeIfPresent(String.self, forKey: .serviceTrackID)
        pageURL = try c.decodeIfPresent(String.self, forKey: .pageURL)
        artworkURL = try c.decodeIfPresent(String.self, forKey: .artworkURL)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        isrc = try c.decodeIfPresent(String.self, forKey: .isrc)
        appleMusicID = try c.decodeIfPresent(String.self, forKey: .appleMusicID)
        sectionStart = try c.decodeIfPresent(Double.self, forKey: .sectionStart)
        sectionEnd = try c.decodeIfPresent(Double.self, forKey: .sectionEnd)
        postedAt = try c.decode(Date.self, forKey: .postedAt)
        roundDay = try c.decode(String.self, forKey: .roundDay)
        comments = try c.decodeIfPresent([CommentRecord].self, forKey: .comments)
    }
}

/// `comments`, as embedded under a submission.
struct CommentRecord: Decodable, Sendable {
    let id: Int
    let authorID: String
    let body: String
    let createdAt: Date

    init(id: Int, authorID: String, body: String, createdAt: Date) {
        self.id = id
        self.authorID = authorID
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, body
        case authorID = "author_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        authorID = try c.decodeID(.authorID)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// `chat_messages`.
struct ChatRecord: Decodable, Sendable {
    let id: String
    let groupID: String
    let authorID: String
    let body: String
    let mentionedSubmissionID: Int?
    let createdAt: Date

    init(
        id: String, groupID: String, authorID: String, body: String,
        mentionedSubmissionID: Int?, createdAt: Date
    ) {
        self.id = id
        self.groupID = groupID
        self.authorID = authorID
        self.body = body
        self.mentionedSubmissionID = mentionedSubmissionID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, body
        case groupID = "group_id"
        case authorID = "author_id"
        case mentionedSubmissionID = "mentioned_submission_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeID(.id)
        groupID = try c.decodeID(.groupID)
        authorID = try c.decodeID(.authorID)
        body = try c.decode(String.self, forKey: .body)
        mentionedSubmissionID = try c.decodeIfPresent(Int.self, forKey: .mentionedSubmissionID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// `votes`.
struct VoteRecord: Decodable, Sendable {
    let submissionID: Int
    let groupID: String
    let roundDay: String
    let voterID: String
    let rating: Int
    let note: String?

    init(
        submissionID: Int, groupID: String, roundDay: String, voterID: String,
        rating: Int, note: String?
    ) {
        self.submissionID = submissionID
        self.groupID = groupID
        self.roundDay = roundDay
        self.voterID = voterID
        self.rating = rating
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case rating, note
        case submissionID = "submission_id"
        case groupID = "group_id"
        case roundDay = "round_day"
        case voterID = "voter_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        submissionID = try c.decode(Int.self, forKey: .submissionID)
        groupID = try c.decodeID(.groupID)
        roundDay = try c.decode(String.self, forKey: .roundDay)
        voterID = try c.decodeID(.voterID)
        rating = try c.decode(Int.self, forKey: .rating)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// `hidden_gems`.
struct GemRecord: Decodable, Sendable {
    let voterID: String
    let groupID: String
    let roundDay: String
    let submissionID: Int

    init(voterID: String, groupID: String, roundDay: String, submissionID: Int) {
        self.voterID = voterID
        self.groupID = groupID
        self.roundDay = roundDay
        self.submissionID = submissionID
    }

    private enum CodingKeys: String, CodingKey {
        case voterID = "voter_id"
        case groupID = "group_id"
        case roundDay = "round_day"
        case submissionID = "submission_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voterID = try c.decodeID(.voterID)
        groupID = try c.decodeID(.groupID)
        roundDay = try c.decode(String.self, forKey: .roundDay)
        submissionID = try c.decode(Int.self, forKey: .submissionID)
    }
}
