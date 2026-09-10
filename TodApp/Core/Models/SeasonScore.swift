import Foundation

/// One member's running total across every round that has been revealed.
struct SeasonTotal: Identifiable, Equatable, Sendable {
    var id: String { memberID }
    var memberID: String
    var name: String
    var points: Int
    /// How many of this member's songs have been through a reveal. A total of
    /// zero from six rounds means something different from zero from none.
    var roundsPlayed: Int
}

/// The season table: what each member's songs have scored so far.
///
/// The first place this app needs a number that spans rounds -- `RoundScore`
/// is one day's, and the seeded `BoardEntry` list is fiction from the
/// prototype. Kept free of SwiftUI so it can be checked on its own.
enum SeasonScore {
    /// Sums the points of each member's own submissions. A member who has
    /// never posted still appears, on zero -- a group's table should list the
    /// group, not only the people who happened to score.
    static func totals(
        members: [Member],
        submissions: [Submission],
        scores: [RoundScore]
    ) -> [SeasonTotal] {
        let pointsBySubmission = Dictionary(
            scores.map { ($0.submissionID, $0.points) },
            uniquingKeysWith: { first, _ in first }
        )

        return members.map { member in
            let own = submissions.filter { $0.posterID == member.id }
            let counted = own.filter { pointsBySubmission[$0.id] != nil }
            return SeasonTotal(
                memberID: member.id,
                name: member.name,
                points: counted.reduce(0) { $0 + (pointsBySubmission[$1.id] ?? 0) },
                roundsPlayed: counted.count
            )
        }
        // Highest first, then by name so a tie has a stable order rather than
        // whatever the member list happened to hold.
        .sorted { ($0.points, $1.name) > ($1.points, $0.name) }
    }
}
