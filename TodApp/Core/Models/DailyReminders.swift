import Foundation

/// The two daily nudges: at 15:00 to post, at 20:00 to vote.
///
/// A calendar trigger cannot look at anything when it fires, so whether a
/// reminder should arrive is settled when it is planned -- and the plan is
/// made again whenever the answer can change: groups loaded, a song posted,
/// the app coming back to the front. Pure, so it is tested without a
/// notification centre or a clock.
///
/// One-shot requests for a week of days rather than one repeating trigger:
/// a repeating 15:00 request would fire on a day the user had already posted,
/// because a single day of it cannot be cancelled.
enum DailyReminders {
    enum Kind: String, Sendable { case post, vote }

    /// How one group stands for the current user today.
    struct GroupStatus: Equatable, Sendable {
        var name: String
        var hasPostedToday: Bool
    }

    struct Reminder: Equatable, Sendable {
        var id: String
        var kind: Kind
        /// Year, month, day, hour and minute -- what a calendar trigger matches.
        var fireAt: DateComponents
        var title: String
        var body: String
    }

    static let postHour = 15
    static let voteHour = 20
    /// Days planned ahead, today included. Someone who has not opened the app
    /// for a week stops being reminded; by then the nudge has not worked.
    static let daysPlanned = 7
    /// Every id starts with this, so a new plan can clear the old one without
    /// touching anything else the app schedules.
    static let idPrefix = "tod.reminder."

    static func plan(
        for groups: [GroupStatus],
        now: Date,
        calendar: Calendar = .current
    ) -> [Reminder] {
        // Nothing to post into, nothing to vote on.
        guard !groups.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var reminders: [Reminder] = []

        for offset in 0..<daysPlanned {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            // Only today is known. On a later day nobody has posted yet, and
            // when that changes the app is open to plan again -- posting only
            // happens in here.
            let open = offset == 0 ? groups.filter { !$0.hasPostedToday } : groups
            if !open.isEmpty, let fire = time(postHour, on: day, calendar), fire > now {
                reminders.append(Reminder(
                    id: id(.post, on: day, calendar: calendar),
                    kind: .post,
                    fireAt: components(of: fire, calendar),
                    title: "Noch kein Song heute",
                    body: "In \(listed(open.map(\.name))) fehlt dein Track of the day. Bis Mitternacht zählt er noch."
                ))
            }

            // Goes to everyone, posted or not: rating is its own job.
            if let fire = time(voteHour, on: day, calendar), fire > now {
                reminders.append(Reminder(
                    id: id(.vote, on: day, calendar: calendar),
                    kind: .vote,
                    fireAt: components(of: fire, calendar),
                    title: "Zeit zum Voten",
                    body: "Die Songs von heute warten auf deine Wertung. Um Mitternacht wird aufgedeckt."
                ))
            }
        }
        return reminders
    }

    /// One id per kind and calendar day, so planning the same day twice
    /// replaces rather than doubles.
    static func id(_ kind: Kind, on day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return idPrefix + kind.rawValue + "." + date
    }

    /// "A", "A und B", "A, B und C" -- written out rather than left to a list
    /// formatter, which follows the device language instead of the app's.
    static func listed(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        let rest = names.dropLast()
        return rest.isEmpty ? last : rest.joined(separator: ", ") + " und " + last
    }

    private static func time(_ hour: Int, on day: Date, _ calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func components(of date: Date, _ calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}
