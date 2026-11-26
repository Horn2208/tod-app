import Foundation
import Testing
@testable import TodApp

/// Who wrote what, and when, said once per run.
@Suite
struct ChatLayoutTests {
    private let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!

    private func message(_ author: String, at minutes: Double, mine: Bool = false) -> ChatMessage {
        ChatMessage(
            id: UUID(), authorTag: String(author.prefix(2)).uppercased(), authorName: author,
            text: "…", isFromCurrentUser: mine, authorID: author,
            sentAt: start.addingTimeInterval(minutes * 60))
    }

    /// Lena twice, then Max: Lena's name once at the top, her avatar at
    /// her second bubble; Max gets both on his one.
    @Test
    func aRunCarriesTheNameFirstAndTheAvatarLast() {
        let layout = ChatLayout.decorations(for: [
            message("Lena", at: 0), message("Lena", at: 1), message("Max", at: 2),
        ])
        #expect(layout.map(\.showsName) == [true, false, true])
        #expect(layout.map(\.showsAvatar) == [false, true, true])
    }

    /// One's own bubbles need neither.
    @Test
    func ownMessagesCarryNoNameNorAvatar() {
        let layout = ChatLayout.decorations(for: [message("me", at: 0, mine: true)])
        #expect(layout == [ChatLayout.Decoration(separator: start, showsName: false, showsAvatar: false)])
    }

    /// The first message, and any after a quarter of an hour's quiet, get the
    /// time above them -- and the name again, as after any silence.
    @Test
    func aLongPauseStartsANewStretch() {
        let layout = ChatLayout.decorations(for: [
            message("Lena", at: 0), message("Lena", at: 5), message("Lena", at: 30),
        ])
        #expect(layout.map(\.separator) == [start, nil, start.addingTimeInterval(30 * 60)])
        #expect(layout.map(\.showsName) == [true, false, true])
        #expect(layout.map(\.showsAvatar) == [false, true, true])
    }

    /// Messages without a time (the demo data) show no times at all.
    @Test
    func noTimeNoSeparator() {
        let undated = ChatMessage(id: UUID(), authorTag: "LE", authorName: "Lena", text: "…", isFromCurrentUser: false)
        #expect(ChatLayout.decorations(for: [undated, undated]).map(\.separator) == [nil, nil])
    }

    @Test
    func todayAndYesterdayAreSaidSo() {
        #expect(ChatLayout.timeLabel(for: start, now: start).hasPrefix("Heute "))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        #expect(ChatLayout.timeLabel(for: yesterday, now: start).hasPrefix("Gestern "))
    }
}
