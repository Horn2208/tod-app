import Foundation

/// A round's day as the database writes it: `yyyy-MM-dd`.
///
/// The database works a post's day out in Europe/Berlin (`submissions.round_day`
/// and `private.today()`); the app decides "today" with the phone's calendar.
/// For people in Germany the two agree.
enum RoundDay {
    /// The calendar day `date` falls on in `calendar`'s time zone. Always
    /// written with Gregorian years, whatever calendar the phone is set to --
    /// the database has only the one.
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The database's own rule for the day a post belongs to.
    static func berlin(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlinZone
        return string(for: date, calendar: calendar)
    }

    private static let berlinZone = TimeZone(identifier: "Europe/Berlin") ?? .current
}
