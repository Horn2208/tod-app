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

    static func previewText(for group: Group) -> String {
        guard let latest = latestSubmission(in: group) else { return "Noch nichts gepostet" }
        return "\(latest.track) – \(latest.artist)"
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
        calendar: Calendar = .current
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
    }

    static func storyBubble(
        for member: Member,
        in groups: [Group],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> StoryBubble? {
        guard let post = latestPost(by: member, in: groups),
              calendar.isDate(post.1.postedAt, inSameDayAs: today) else { return nil }
        return StoryBubble(track: post.1.track, artist: post.1.artist)
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
            switch (latestSubmission(in: left)?.postedAt, latestSubmission(in: right)?.postedAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.name < right.name
            }
        }
    }
}
