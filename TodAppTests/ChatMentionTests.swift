import Foundation
import Testing
@testable import TodApp

@Suite
struct ChatMentionTests {
    private let calendar = Calendar.current
    private let today = Date()

    private func song(_ id: Int, postedAt: Date) -> Submission {
        Submission(
            id: id, posterID: "lena", track: "Passionfruit", artist: "Drake",
            coverColorHex: "#000000", comments: [], postedAt: postedAt
        )
    }

    @Test
    func aSongFromTodayOpensTheRunningFeed() {
        let target = ChatMention.target(for: song(2, postedAt: today), today: today, calendar: calendar)
        #expect(target == .today(submissionID: 2))
    }

    @Test
    func aSongFromYesterdayOpensTheReveal() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let target = ChatMention.target(for: song(9, postedAt: yesterday), today: today, calendar: calendar)
        #expect(target == .yesterday(submissionID: 9))
    }

    @Test
    func anOlderSongOpensAlone() {
        let older = calendar.date(byAdding: .day, value: -4, to: today)!
        let target = ChatMention.target(for: song(80, postedAt: older), today: today, calendar: calendar)
        #expect(target == .older(submissionID: 80))
    }
}
