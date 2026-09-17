import Foundation

/// Turns the database's rows into the `Group` values every screen already
/// reads. Pure, so the whole mapping is checked without a server.
///
/// What the tables do not store is derived here, the same way the in-memory
/// data derives it: who has posted on which day (from the posts), when the
/// round ends (midnight), a song's fallback colour (from its track), and who
/// the signed-in user is (from the account, not a flag in a row).
enum GroupAssembly {
    /// Shown for someone whose profile the server does not return.
    static let unknownName = "Jemand"

    static func groups(
        from groups: [GroupRecord],
        submissions: [SubmissionRecord],
        messages: [ChatRecord],
        images: [String: Data],
        me: String,
        now: Date,
        calendar: Calendar = .current
    ) -> [Group] {
        let postsByGroup = Dictionary(grouping: submissions, by: \.groupID)
        let messagesByGroup = Dictionary(grouping: messages, by: \.groupID)
        let roundEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        return groups
            .map { row in
                let posts = (postsByGroup[row.id] ?? []).sorted(by: postOrder)
                let names = Dictionary(
                    row.members.map { ($0.userID, $0.profile?.name ?? unknownName) },
                    uniquingKeysWith: { first, _ in first })
                return Group(
                    id: row.id,
                    name: row.name,
                    icon: row.icon,
                    imageData: row.imagePath.flatMap { images[$0] },
                    members: members(of: row, posts: posts, me: me),
                    roundEndsAt: roundEnd,
                    submissions: posts.map { submission(from: $0, names: names) },
                    chatMessages: (messagesByGroup[row.id] ?? [])
                        .sorted { $0.createdAt < $1.createdAt }
                        .compactMap { message(from: $0, names: names, me: me) },
                    activeBattle: nil,
                    creatorID: row.creatorID ?? "",
                    invitePolicy: row.invitePolicy == "creator_only" ? .creatorOnly : .everyone
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Two letters for an avatar without a picture, as the rest of the app
    /// draws them.
    static func initials(of name: String) -> String {
        String(name.prefix(2)).uppercased()
    }

    private static func postOrder(_ left: SubmissionRecord, _ right: SubmissionRecord) -> Bool {
        left.postedAt == right.postedAt ? left.id < right.id : left.postedAt < right.postedAt
    }

    /// The signed-in user first, everyone else by name.
    private static func members(of row: GroupRecord, posts: [SubmissionRecord], me: String) -> [Member] {
        let days = Dictionary(grouping: posts, by: \.posterID).mapValues { $0.map(\.postedAt) }
        return row.members
            .map { member in
                Member(
                    id: member.userID,
                    name: member.profile?.name ?? unknownName,
                    isCurrentUser: member.userID == me,
                    postedDates: days[member.userID] ?? []
                )
            }
            .sorted { left, right in
                if left.isCurrentUser != right.isCurrentUser { return left.isCurrentUser }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private static func submission(from row: SubmissionRecord, names: [String: String]) -> Submission {
        let source = trackSource(of: row)
        let section: TrackSection? = if let start = row.sectionStart, let end = row.sectionEnd {
            TrackSection(start: start, end: end)
        } else {
            nil
        }
        return Submission(
            id: row.id,
            posterID: row.posterID,
            track: row.track,
            artist: row.artist,
            // Keyed like a fresh post, so a song keeps its colour once it has
            // gone through the server.
            coverColorHex: CoverColor.hex(forTrack: row.serviceTrackID ?? "\(row.track)|\(row.artist)"),
            comments: (row.comments ?? [])
                .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
                .map { comment in
                    Comment(
                        id: comment.id,
                        authorID: comment.authorID,
                        authorName: names[comment.authorID] ?? unknownName,
                        text: comment.body,
                        postedAt: comment.createdAt
                    )
                },
            source: source,
            section: section,
            isrc: row.isrc,
            appleMusicID: row.appleMusicID,
            postedAt: row.postedAt
        )
    }

    /// A source only when all of it is there and the app knows the service.
    private static func trackSource(of row: SubmissionRecord) -> TrackSource? {
        guard let raw = row.service, let service = MusicService(rawValue: raw),
              let trackID = row.serviceTrackID,
              let page = row.pageURL.flatMap(URL.init(string:))
        else { return nil }
        return TrackSource(
            service: service,
            serviceTrackID: trackID,
            pageURL: page,
            artworkURL: row.artworkURL.flatMap(URL.init(string:))
        )
    }

    private static func message(from row: ChatRecord, names: [String: String], me: String) -> ChatMessage? {
        guard let id = UUID(uuidString: row.id) else { return nil }
        let isMine = row.authorID == me
        let name = names[row.authorID] ?? unknownName
        return ChatMessage(
            id: id,
            authorTag: isMine ? "DU" : initials(of: name),
            authorName: isMine ? "Du" : name,
            text: row.body,
            isFromCurrentUser: isMine,
            mentionedSubmissionID: row.mentionedSubmissionID
        )
    }
}
