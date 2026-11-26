import Foundation

/// The month grid behind the streak: which days you posted on, laid out the way
/// a calendar is. Pure, so the layout is tested without a view.
enum StreakCalendar {
    struct Day: Equatable, Sendable {
        let date: Date
        let number: Int
        let posted: Bool
        let isToday: Bool
        /// Still to come -- nothing to show yet, and not a missed day either.
        let isFuture: Bool
    }

    /// Monday first, in German. The app speaks German throughout, and a week
    /// that starts on Sunday reads as foreign here -- whatever region the
    /// phone happens to be set to.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }

    /// The month containing `date`, as rows of seven. Cells outside the month
    /// are nil, so the first of the month sits under its own weekday.
    static func weeks(
        ofMonthContaining date: Date,
        postedDates: [Date],
        today: Date = Date(),
        calendar: Calendar = StreakCalendar.calendar
    ) -> [[Day?]] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let dayCount = calendar.range(of: .day, in: .month, for: date)?.count
        else { return [] }
        let postedDays = Set(postedDates.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)

        // Empty cells before the 1st: its weekday, counted from the calendar's
        // first weekday rather than from Sunday.
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Day?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: month.start) else { continue }
            let start = calendar.startOfDay(for: day)
            cells.append(Day(
                date: start,
                number: offset + 1,
                posted: postedDays.contains(start),
                isToday: start == todayStart,
                isFuture: start > todayStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// "Mo", "Di", … in the calendar's own order, without the trailing dot some
    /// systems put on German abbreviations.
    static func weekdaySymbols(calendar: Calendar = StreakCalendar.calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map {
            $0.replacingOccurrences(of: ".", with: "")
        }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// "September 2026".
    static func title(ofMonthContaining date: Date, calendar: Calendar = StreakCalendar.calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    /// Paging back stops at the month of the first post: earlier months would
    /// only be empty grids. Without any post, the current month is all there is.
    static func earliestMonth(
        postedDates: [Date],
        today: Date = Date(),
        calendar: Calendar = StreakCalendar.calendar
    ) -> Date {
        let first = min(postedDates.min() ?? today, today)
        return calendar.dateInterval(of: .month, for: first)?.start ?? today
    }

    /// Paging forward stops at the current month: the future has nothing to show.
    static func latestMonth(today: Date = Date(), calendar: Calendar = StreakCalendar.calendar) -> Date {
        calendar.dateInterval(of: .month, for: today)?.start ?? today
    }
}
