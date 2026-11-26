import Foundation
import Testing
@testable import TodApp

@Suite
struct StreakTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: today)!
    }

    @Test
    func noPostsIsNoStreak() {
        #expect(Streak.current(from: [], today: today, calendar: calendar) == 0)
    }

    @Test
    func postingTodayOnlyIsOne() {
        #expect(Streak.current(from: [today], today: today, calendar: calendar) == 1)
    }

    @Test
    func threeDaysInARowCountsThree() {
        let dates = [daysAgo(2), daysAgo(1), today]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 3)
    }

    /// The day is not over yet: someone who posted yesterday and the days
    /// before still holds their streak until midnight.
    @Test
    func yesterdayStillCountsWhenTodayIsUnfinished() {
        let dates = [daysAgo(2), daysAgo(1)]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 2)
    }

    @Test
    func aMissedDayEndsTheStreak() {
        let dates = [daysAgo(5), daysAgo(4), daysAgo(1), today]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 2)
    }

    /// Two posts on one day are one day, not two.
    @Test
    func twoPostsOnTheSameDayCountOnce() {
        let dates = [today, today.addingTimeInterval(120)]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 1)
    }

    @Test
    func postsFromLongAgoDoNotCount() {
        #expect(Streak.current(from: [daysAgo(30)], today: today, calendar: calendar) == 0)
    }
}

/// "Has posted today" follows the posting dates, the way the streak does.
@Suite
struct PostedTodayTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let noon = Calendar(identifier: .gregorian)
        .startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        .addingTimeInterval(12 * 3600)

    @Test
    func aPostEarlierTodayCounts() {
        #expect(Member.hasPosted(on: noon, in: [noon.addingTimeInterval(-3600)], calendar: calendar))
    }

    @Test
    func noPostsIsNotPosted() {
        #expect(Member.hasPosted(on: noon, in: [], calendar: calendar) == false)
    }

    /// The bug this replaced: a flag set by yesterday's post and never cleared.
    /// One minute to midnight yesterday is not today at one minute past.
    @Test
    func yesterdaysPostDoesNotRingToday() {
        let dayStart = calendar.startOfDay(for: noon)
        let lastNight = dayStart.addingTimeInterval(-60)
        let justAfterMidnight = dayStart.addingTimeInterval(60)

        #expect(Member.hasPosted(on: justAfterMidnight, in: [lastNight], calendar: calendar) == false)
    }
}
