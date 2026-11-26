import Foundation

/// How many days in a row someone has posted. Pure arithmetic over dates, so
/// it can be tested without a view, a store, or a clock.
enum Streak {
    /// Counts back from today. A gap ends the count. Today itself may be
    /// missing without breaking the streak -- the day is not over, and
    /// resetting someone's number at midnight for a day they can still finish
    /// would be the wrong kind of honest.
    static func current(
        from dates: [Date],
        today: Date = Date(),
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            // Today is still open. Start counting from yesterday instead.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return count
    }
}
