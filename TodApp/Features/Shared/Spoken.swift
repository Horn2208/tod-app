import Foundation

/// What VoiceOver says for things the eye takes in at a glance: a card, a
/// row, a progress bar. Pure text rules, tested without a view -- the same
/// reason `CommentTime` sits beside its screen rather than inside it.
enum Spoken {
    /// "3:07". Also what is printed under the player.
    static func time(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// A song as one sentence, instead of two labels read one after another.
    static func song(track: String, artist: String) -> String {
        artist.isEmpty ? track : "\(track) von \(artist)"
    }

    /// Where playback stands. Without a length -- nothing has said one yet --
    /// the position alone, rather than "von 0:00".
    static func playback(position: Double, duration: Double) -> String {
        duration > 0 ? "\(time(position)) von \(time(duration))" : time(position)
    }

    /// Someone in the story row. The ring around their picture says they have
    /// posted today; said here, because a ring is not.
    static func storyMember(name: String, isCurrentUser: Bool, hasPostedToday: Bool) -> String {
        let who = isCurrentUser ? "Du" : name
        return hasPostedToday ? "\(who), hat heute gepostet" : "\(who), heute noch nichts"
    }

    /// A comment: who said it, when, and what. The initials in the circle
    /// beside it are not part of what was said.
    static func comment(author: String, time: String, text: String) -> String {
        "\(author), \(time), \(text)"
    }

    /// A leaderboard row: who, how many points, over how many rounds, and
    /// whether they are ahead -- the crown says that to the eye alone.
    static func leaderboardRow(name: String, points: Int, subtitle: String, isLeader: Bool) -> String {
        let unit = abs(points) == 1 ? "Punkt" : "Punkte"
        let lead = isLeader ? "führt, " : ""
        return "\(lead)\(name), \(points) \(unit), \(subtitle)"
    }

    /// "💎 3" read out loud is "Edelstein 3".
    static func gems(_ count: Int) -> String {
        count == 1 ? "1 Hidden Gem" : "\(count) Hidden Gems"
    }

    /// A group row: its name, what is new in it, and when.
    static func groupRow(name: String, preview: String, time: String?) -> String {
        [name, preview, time]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
