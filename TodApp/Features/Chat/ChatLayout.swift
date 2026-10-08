import Foundation

/// How the chat dresses each message: whose it is and when, said once per
/// run rather than on every bubble, the way a messenger does (the brief's
/// audit, 8. Oktober: in a group of more than two nobody could tell who
/// wrote what). Pure, so the rules are tested without SwiftUI.
enum ChatLayout {
    /// A gap this long starts a new stretch, with the time above it.
    static let pause: TimeInterval = 15 * 60

    struct Decoration: Equatable {
        /// The time to show above this message, when a new stretch starts.
        var separator: Date?
        /// The sender's name above the bubble: the first of their run.
        var showsName: Bool
        /// The sender's avatar beside the bubble: the last of their run.
        var showsAvatar: Bool
    }

    static func decorations(for messages: [ChatMessage]) -> [Decoration] {
        messages.indices.map { index in
            let message = messages[index]
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let separator = startsStretch(message, after: previous) ? message.sentAt : nil
            // A new stretch begins a new run too: the name comes again after
            // the time, as it would after a long silence.
            let startsRun = (previous.map { !sameAuthor($0, message) } ?? true) || separator != nil
            let endsRun = next.map { !sameAuthor($0, message) || startsStretch($0, after: message) } ?? true
            return Decoration(
                separator: separator,
                showsName: !message.isFromCurrentUser && startsRun,
                showsAvatar: !message.isFromCurrentUser && endsRun)
        }
    }

    private static func startsStretch(_ message: ChatMessage, after previous: ChatMessage?) -> Bool {
        guard let sent = message.sentAt else { return false }
        guard let previous else { return true }
        guard let before = previous.sentAt else { return false }
        return sent.timeIntervalSince(before) >= pause
    }

    private static func sameAuthor(_ left: ChatMessage, _ right: ChatMessage) -> Bool {
        if let a = left.authorID, let b = right.authorID { return a == b }
        return left.isFromCurrentUser == right.isFromCurrentUser && left.authorName == right.authorName
    }

    /// "Heute 14:05", "Gestern 20:10", or the date for anything older.
    static func timeLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "de_DE")))
        if calendar.isDate(date, inSameDayAs: now) { return "Heute \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Gestern \(time)"
        }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "de_DE")))
        return "\(day) \(time)"
    }

    /// A message named in a confirmation: its first words, or what it
    /// carries when it has none of its own.
    static func excerpt(of message: ChatMessage, limit: Int = 40) -> String {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return message.mentionedSubmissionID == nil ? "Nachricht" : "Song-Erwähnung" }
        guard text.count > limit else { return text }
        return text.prefix(limit).trimmingCharacters(in: .whitespaces) + " …"
    }
}
