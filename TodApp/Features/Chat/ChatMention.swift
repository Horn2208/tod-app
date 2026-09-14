import Foundation

/// Where a tap on a song mentioned in chat should land. Same idea as
/// `GroupsFeed.storyTarget`: today's song opens the running feed, yesterday's
/// the reveal, anything older opens alone because it belongs to no round
/// still on screen.
enum ChatMention {
    enum Target: Equatable {
        case today(submissionID: Int)
        case yesterday(submissionID: Int)
        case older(submissionID: Int)
    }

    static func target(
        for submission: Submission,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Target {
        if RoundVisibility.isVotable(roundDay: submission.postedAt, today: today, calendar: calendar) {
            return .today(submissionID: submission.id)
        }
        let revealed = RoundVisibility.revealedDay(today: today, calendar: calendar)
        if calendar.isDate(submission.postedAt, inSameDayAs: revealed) {
            return .yesterday(submissionID: submission.id)
        }
        return .older(submissionID: submission.id)
    }
}
