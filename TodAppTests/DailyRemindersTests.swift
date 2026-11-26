import Foundation
import Testing
@testable import TodApp

@Suite
struct DailyRemindersTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private let open = DailyReminders.GroupStatus(name: "LNC", hasPostedToday: false)
    private let done = DailyReminders.GroupStatus(name: "WG", hasPostedToday: true)

    private func plan(_ groups: [DailyReminders.GroupStatus], at now: Date) -> [DailyReminders.Reminder] {
        DailyReminders.plan(for: groups, now: now, calendar: calendar)
    }

    private func ids(_ groups: [DailyReminders.GroupStatus], at now: Date) -> [String] {
        plan(groups, at: now).map(\.id)
    }

    @Test
    func aMorningWithAnOpenGroupRemindsToPostAtThree() {
        let first = plan([open], at: date(11, 9)).first

        #expect(first?.id == "tod.reminder.post.2026-09-11")
        #expect(first?.fireAt.day == 11)
        #expect(first?.fireAt.hour == 15)
        #expect(first?.fireAt.minute == 0)
    }

    /// Posting takes back today's post reminder and nothing else: the vote
    /// still comes, and tomorrow's post reminder still stands.
    @Test
    func postedEverywhereDropsOnlyTodaysPostReminder() {
        let planned = ids([done], at: date(11, 9))

        #expect(!planned.contains("tod.reminder.post.2026-09-11"))
        #expect(planned.contains("tod.reminder.vote.2026-09-11"))
        #expect(planned.contains("tod.reminder.post.2026-09-12"))
    }

    @Test
    func oneOpenGroupIsEnoughAndOnlyItIsNamed() {
        let today = plan([open, done], at: date(11, 9))
            .first { $0.id == "tod.reminder.post.2026-09-11" }

        #expect(today?.body.contains("LNC") == true)
        #expect(today?.body.contains("WG") == false)
    }

    /// Nobody has posted on a day that has not started, so a later day's
    /// reminder names every group -- including one finished today.
    @Test
    func laterDaysNameEveryGroup() {
        let tomorrow = plan([open, done], at: date(11, 9))
            .first { $0.id == "tod.reminder.post.2026-09-12" }

        #expect(tomorrow?.body.contains("LNC und WG") == true)
    }

    @Test
    func afterThreeOnlyTheVoteIsLeftToday() {
        let today = ids([open], at: date(11, 16)).filter { $0.hasSuffix("2026-09-11") }

        #expect(today == ["tod.reminder.vote.2026-09-11"])
    }

    /// A reminder for the minute that is already here would never arrive.
    @Test
    func exactlyAtThreeIsTooLateForToday() {
        #expect(!ids([open], at: date(11, 15)).contains("tod.reminder.post.2026-09-11"))
    }

    @Test
    func afterEightTodayIsOver() {
        let planned = ids([open], at: date(11, 21))

        #expect(!planned.contains { $0.hasSuffix("2026-09-11") })
        #expect(planned.first == "tod.reminder.post.2026-09-12")
    }

    @Test
    func aWeekIsPlannedAndNoMore() {
        let planned = ids([open], at: date(11, 9))

        #expect(planned.count == 14)
        #expect(planned.contains("tod.reminder.vote.2026-09-17"))
        #expect(!planned.contains { $0.hasSuffix("2026-09-18") })
    }

    @Test
    func noGroupsMeansNoReminders() {
        #expect(plan([], at: date(11, 9)).isEmpty)
    }

    /// The clocks go back on 25 October. Adding 24 hours to 15:00 would land
    /// on 14:00 that day; the reminder has to stay at three.
    @Test
    func theClockChangeDoesNotMoveThreeOClock() {
        let posts = plan([open], at: date(24, 9, month: 10)).filter { $0.kind == .post }

        #expect(posts.count == 7)
        #expect(posts.allSatisfy { $0.fireAt.hour == 15 })
    }

    @Test
    func namesAreListedTheGermanWay() {
        #expect(DailyReminders.listed(["A"]) == "A")
        #expect(DailyReminders.listed(["A", "B"]) == "A und B")
        #expect(DailyReminders.listed(["A", "B", "C"]) == "A, B und C")
    }
}
