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

    // MARK: - What a message shows

    private func message(_ text: String, mentioning submissionID: Int? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID(), authorTag: "LE", authorName: "Lena", text: text,
            isFromCurrentUser: false, mentionedSubmissionID: submissionID
        )
    }

    @Test
    func aMentionKeepsTheTextItWasSentWith() {
        let content = ChatMention.content(
            of: message("hör dir das an", mentioning: 2), in: [song(2, postedAt: today)])
        #expect(content.text == "hör dir das an")
        #expect(content.song?.id == 2)
    }

    @Test
    func aBlankMessageShowsOnlyTheSong() {
        let content = ChatMention.content(
            of: message("  \n", mentioning: 2), in: [song(2, postedAt: today)])
        #expect(content.text == nil)
        #expect(content.song?.id == 2)
    }

    @Test
    func aMentionOfASongNoLongerInTheGroupShowsTheTextAlone() {
        let content = ChatMention.content(
            of: message("der hier", mentioning: 99), in: [song(2, postedAt: today)])
        #expect(content.text == "der hier")
        #expect(content.song == nil)
    }

    @Test
    func aMessageWithoutAMentionIsJustText() {
        let content = ChatMention.content(of: message("Battle heute Abend?"), in: [song(2, postedAt: today)])
        #expect(content.text == "Battle heute Abend?")
        #expect(content.song == nil)
    }
}
