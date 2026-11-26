import Foundation

/// Yesterday's ranking, shown once over Home on the first visit after
/// midnight (Berlin), per group and day. The rules for when, in which order
/// and with which words; the card itself is `RankingOverlayView`.
enum RankingOverlay {
    /// One song in the ranking.
    struct Row: Equatable, Identifiable {
        var id: Int { submission.id }
        var submission: Submission
        /// 1 for the best; a tie shares its place and the next one skips
        /// (1, 2, 2, 4), as a table does.
        var place: Int
        var points: Int
        var gems: Int
        var isOwn: Bool

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.submission.id == rhs.submission.id && lhs.place == rhs.place
                && lhs.points == rhs.points && lhs.gems == rhs.gems && lhs.isOwn == rhs.isOwn
        }
    }

    /// Whether the overlay comes up: there is a revealed day, it has not been
    /// seen here yet, and nothing else is on screen in front of Home.
    static func shouldShowRanking(revealedDay: Date?, lastSeen: Date?, isBlocked: Bool) -> Bool {
        guard let revealedDay, !isBlocked else { return false }
        return lastSeen != revealedDay
    }

    /// The day's songs, best first. A song nobody rated scores 0 rather than
    /// dropping out. Equal points keep posting order and share a place.
    static func ranking(scores: [RoundScore], submissions: [Submission], userID: String) -> [Row] {
        let byID = Dictionary(scores.map { ($0.submissionID, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = submissions
            .sorted { $0.postedAt < $1.postedAt }
            .map { ($0, byID[$0.id]?.points ?? 0, byID[$0.id]?.hiddenGemCount ?? 0) }
            .enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element)
        var rows: [Row] = []
        for (index, entry) in sorted.enumerated() {
            let place = index > 0 && rows[index - 1].points == entry.1 ? rows[index - 1].place : index + 1
            rows.append(Row(
                submission: entry.0, place: place, points: entry.1, gems: entry.2,
                isOwn: entry.0.posterID == userID))
        }
        return rows
    }

    /// "Dein Song: 7 Punkte · Platz 2 von 5", or, without a song of yours,
    /// "5 Songs, sieh dir an, wie bewertet wurde".
    static func resultLine(_ rows: [Row]) -> String {
        guard let own = rows.first(where: \.isOwn) else {
            return rows.count == 1
                ? "1 Song, sieh dir an, wie bewertet wurde"
                : "\(rows.count) Songs, sieh dir an, wie bewertet wurde"
        }
        return "Dein Song: \(points(own.points)) · Platz \(own.place) von \(rows.count)"
    }

    /// What VoiceOver says as the overlay opens.
    static func spokenSummary(_ rows: [Row]) -> String {
        "Gestern ist aufgedeckt. " + resultLine(rows).replacingOccurrences(of: " · ", with: ", ") + "."
    }

    /// "1 Punkt", "7 Punkte", "-1 Punkt".
    static func points(_ value: Int) -> String {
        abs(value) == 1 ? "\(value) Punkt" : "\(value) Punkte"
    }
}

/// Which revealed day was last seen per group, on this phone -- the pattern
/// of `ChatReadMarks`. Set when the overlay is closed or the reveal opened
/// from it; the overlay stays away until the next day.
enum RankingSeenMarks {
    static func key(for groupID: String) -> String {
        "ranking.lastSeen.\(groupID)"
    }

    static func markSeen(_ day: Date, in groupID: String, defaults: UserDefaults = .standard) {
        defaults.set(day.timeIntervalSince1970, forKey: key(for: groupID))
    }

    static func lastSeen(in groupID: String, defaults: UserDefaults = .standard) -> Date? {
        let stored = defaults.double(forKey: key(for: groupID))
        return stored == 0 ? nil : Date(timeIntervalSince1970: stored)
    }

    /// Whether a group has a revealed day not seen yet -- the dot on its
    /// circle in the group switcher.
    static func hasUnseen(_ group: Group, today: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard !RoundVisibility.revealedSubmissions(from: group.submissions, today: today).isEmpty
        else { return false }
        return lastSeen(in: group.id, defaults: defaults) != RoundVisibility.revealedDay(today: today)
    }
}
