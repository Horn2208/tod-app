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
    static func storyMembers(across groups: [Group]) -> [Member] {
        var seen = Set<String>()
        var result: [Member] = []
        for member in groups.flatMap(\.members) where seen.insert(member.id).inserted {
            result.append(member)
        }
        // Whoever has posted today comes first: the row is about what happened
        // today, and the people it is about should not need scrolling to reach.
        return result.sorted { $0.hasPostedToday && !$1.hasPostedToday }
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
