import Foundation
import Testing
@testable import TodApp

@Suite
struct StreakCalendarTests {
    private var calendar: Calendar {
        var calendar = StreakCalendar.calendar
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private var today: Date { date(9, 14, 10) }

    private func september(posted: [Date] = []) -> [[StreakCalendar.Day?]] {
        StreakCalendar.weeks(ofMonthContaining: today, postedDates: posted, today: today, calendar: calendar)
    }

    private func day(_ number: Int, in weeks: [[StreakCalendar.Day?]]) -> StreakCalendar.Day? {
        weeks.joined().compactMap { $0 }.first { $0.number == number }
    }

    /// 1 September 2026 is a Tuesday, so Monday's cell stays empty.
    @Test
    func theFirstSitsUnderItsOwnWeekday() {
        let firstWeek = september()[0]

        #expect(firstWeek[0] == nil)
        #expect(firstWeek[1]?.number == 1)
    }

    /// 1 June 2026 is a Monday: no empty cell before it.
    @Test
    func aMonthStartingOnMondayHasNoGap() {
        let june = StreakCalendar.weeks(
            ofMonthContaining: date(6, 10), postedDates: [], today: today, calendar: calendar)

        #expect(june[0][0]?.number == 1)
    }

    @Test
    func everyDayOfTheMonthAppearsOnceInRowsOfSeven() {
        let weeks = september()

        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.joined().compactMap { $0 }.map(\.number) == Array(1...30))
    }

    @Test
    func postedDaysAreMarked() {
        let weeks = september(posted: [date(9, 3, 18), date(9, 13, 9)])

        #expect(day(3, in: weeks)?.posted == true)
        #expect(day(13, in: weeks)?.posted == true)
        #expect(day(4, in: weeks)?.posted == false)
    }

    /// A post at one minute to midnight belongs to its own day, not the next.
    @Test
    func aLatePostCountsForItsOwnDay() {
        let weeks = september(posted: [date(9, 5, 23, 59)])

        #expect(day(5, in: weeks)?.posted == true)
        #expect(day(6, in: weeks)?.posted == false)
    }

    @Test
    func todayIsMarkedAndLaterDaysAreStillToCome() {
        let weeks = september()

        #expect(day(14, in: weeks)?.isToday == true)
        #expect(day(14, in: weeks)?.isFuture == false)
        #expect(day(15, in: weeks)?.isFuture == true)
        #expect(day(13, in: weeks)?.isFuture == false)
    }

    @Test
    func mondayComesFirst() {
        #expect(StreakCalendar.weekdaySymbols(calendar: calendar) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
    }

    @Test
    func theMonthIsNamedInGerman() {
        #expect(StreakCalendar.title(ofMonthContaining: today, calendar: calendar) == "September 2026")
    }

    @Test
    func pagingBackStopsAtTheMonthOfTheFirstPost() {
        let earliest = StreakCalendar.earliestMonth(
            postedDates: [date(9, 2), date(8, 20)], today: today, calendar: calendar)

        #expect(earliest == calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
    }

    @Test
    func withoutAnyPostTheCurrentMonthIsAllThereIs() {
        #expect(StreakCalendar.earliestMonth(postedDates: [], today: today, calendar: calendar)
                == StreakCalendar.latestMonth(today: today, calendar: calendar))
    }
}
