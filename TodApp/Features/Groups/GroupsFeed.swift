import Foundation

/// The arithmetic behind the groups feed: what the search shows, which song a
/// row previews, and who appears in the story row. Kept out of the view so it
/// can be checked without SwiftUI, the way TrackSection and Streak are.
enum GroupsFeed {
    /// Case- and diacritic-insensitive, because nobody types "WG Chaos" with
    /// the right capitals while looking for it.
    static func matching(_ query: String, in groups: [Group]) -> [Group] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return groups }
        return groups.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The song a row previews: the most recent one posted to that group.
    static func latestSubmission(in group: Group) -> Submission? {
        group.submissions.max { $0.postedAt < $1.postedAt }
    }

    /// What a row shows under the group's name: the newest of its last song
    /// and its last chat message. The row opens the chat, so a song from
    /// three days ago above a lively chat said the wrong thing (the brief's
    /// second audit, B4).
    struct Activity: Equatable {
        var text: String
        /// Nil for the demo chat, which carries no times.
        var at: Date?
    }

    static func latestActivity(in group: Group) -> Activity? {
        let song = latestSubmission(in: group).map {
            Activity(text: "\($0.track) – \($0.artist)", at: $0.postedAt)
        }
        let message = group.chatMessages.last.map { message in
            let who = message.isFromCurrentUser ? "Du" : message.authorName
            let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Activity(
                text: body.isEmpty ? "\(who) hat einen Song erwähnt" : "\(who): \(body)",
                at: message.sentAt)
        }
        switch (song, message) {
        case let (song?, message?):
            // An undated message (demo data) is not known to be newer.
            guard let sent = message.at, let posted = song.at else { return song }
            return sent > posted ? message : song
        case let (song?, nil): return song
        case let (nil, message?): return message
        case (nil, nil): return nil
        }
    }

    static func previewText(for group: Group) -> String {
        latestActivity(in: group)?.text ?? "Noch nichts gepostet"
    }

    /// The time beside a row: the hour today, "gestern", the date before.
    static func timeLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let german = Locale(identifier: "de_DE")
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(german))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern"
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(german))
    }

    /// A dot for a chat with something new: the last message is someone
    /// else's and is not the last one seen here (`ChatReadMarks`).
    static func hasUnread(in group: Group, lastSeenID: String?) -> Bool {
        guard let last = group.chatMessages.last, !last.isFromCurrentUser else { return false }
        return last.id.uuidString != lastSeenID
    }

    /// Everyone across every group, each appearing once. Someone in two groups
    /// is still one person, and two circles for them would read as two people.
    /// Posting in any one of their groups is enough to ring them here -- the
    /// question this row answers is "did they post today", not "did they post
    /// in this particular group", so their posting dates are merged across
    /// duplicates rather than taken from whichever group happened to come first.
    static func storyMembers(across groups: [Group]) -> [Member] {
        var order: [String] = []
        var byID: [String: Member] = [:]
        for member in groups.flatMap(\.members) {
            if var existing = byID[member.id] {
                existing.postedDates += member.postedDates
                byID[member.id] = existing
            } else {
                byID[member.id] = member
                order.append(member.id)
            }
        }
        let result = order.compactMap { byID[$0] }
        // You first, then whoever has posted today. The row is about what
        // happened today, and the people it is about should not need scrolling
        // to reach -- least of all the person holding the phone.
        return result.sorted { left, right in
            if left.isCurrentUser != right.isCurrentUser { return left.isCurrentUser }
            return left.hasPostedToday && !right.hasPostedToday
        }
    }

    /// Where a tap on someone in the story row leads. Today's song opens the
    /// running round's feed at their card, yesterday's the reveal at theirs.
    /// Anything older belongs to no round on screen any more and opens alone.
    enum StoryTarget: Equatable {
        case today(groupID: String, submissionID: Int)
        case yesterday(groupID: String, submissionID: Int)
        case older(submissionID: Int)
    }

    static func storyTarget(
        for member: Member,
        in groups: [Group],
        today: Date = Date(),
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> StoryTarget? {
        guard let post = latestPost(by: member, in: groups) else { return nil }
        let (group, song) = post
        if RoundVisibility.isVotable(roundDay: song.postedAt, today: today, calendar: calendar) {
            return .today(groupID: group.id, submissionID: song.id)
        }
        let revealed = RoundVisibility.revealedDay(today: today, calendar: calendar)
        if calendar.isDate(song.postedAt, inSameDayAs: revealed) {
            return .yesterday(groupID: group.id, submissionID: song.id)
        }
        return .older(submissionID: song.id)
    }

    /// A feed opened from someone in the story row starts at their card. The
    /// card moves to the front rather than being scrolled to: scrolling a paged
    /// feed to a later card lined it up under the navigation bar, or did not
    /// scroll at all -- measured three ways. The rest keep their order behind it.
    static func feedOrder(_ submissions: [Submission], startingAt submissionID: Int?) -> [Submission] {
        guard let submissionID,
              let index = submissions.firstIndex(where: { $0.id == submissionID })
        else { return submissions }
        var rest = submissions
        let chosen = rest.remove(at: index)
        return [chosen] + rest
    }

    /// The song in the bubble above someone's circle: what they posted today,
    /// and nothing on a day they have not. The ring says that they posted;
    /// the bubble says what.
    struct StoryBubble: Equatable {
        let track: String
        let artist: String
        var coverURL: URL? = nil
        var coverColorHex: String = "#37313b"
    }

    static func storyBubble(
        for member: Member,
        in groups: [Group],
        today: Date = Date(),
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> StoryBubble? {
        guard let post = latestPost(by: member, in: groups),
              calendar.isDate(post.1.postedAt, inSameDayAs: today) else { return nil }
        return StoryBubble(
            track: post.1.track, artist: post.1.artist,
            coverURL: post.1.coverURL, coverColorHex: post.1.coverColorHex)
    }

    /// Someone's newest post across every group, with the group it went to --
    /// the feed that opens has to be that group's.
    private static func latestPost(by member: Member, in groups: [Group]) -> (Group, Submission)? {
        groups
            .flatMap { group in
                group.submissions.filter { $0.posterID == member.id }.map { (group, $0) }
            }
            .max { $0.1.postedAt < $1.1.postedAt }
    }

    /// Newest group first, so the feed reads like a conversation list. A group
    /// nobody has posted to yet sinks to the bottom rather than claiming the
    /// top with an absent date.
    static func ordered(_ groups: [Group]) -> [Group] {
        groups.sorted { left, right in
            switch (latestActivity(in: left)?.at, latestActivity(in: right)?.at) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.name < right.name
            }
        }
    }
}
