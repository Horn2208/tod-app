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

    /// What a message shows: the text it was sent with, unless it has none, and
    /// the song it mentions. A mention of a song no longer in the group falls
    /// back to the text alone rather than an empty card.
    struct Content {
        let text: String?
        let song: Submission?
    }

    static func content(of message: ChatMessage, in submissions: [Submission]) -> Content {
        let isBlank = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let song = message.mentionedSubmissionID.flatMap { id in submissions.first { $0.id == id } }
        return Content(text: isBlank ? nil : message.text, song: song)
    }
}
