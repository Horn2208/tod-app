import Foundation

/// Which catalog song, if any, is the one that was posted.
///
/// A text search is not an answer by itself. Measured: asking the iTunes
/// Search API for "Nights Frank Ocean" puts Martin Garrix's "Ocean (feat.
/// Khalid)" first, and the real "Nights" is not among fifty hits at all --
/// "Blonde" is not sold in the iTunes Store. So a hit counts only when the
/// title -- a remix or a live take included -- and the lead artist agree and
/// the length is within a few seconds. Otherwise there is no match, and the
/// player falls back to Spotify's embed: no song beats the wrong recording.
///
/// An ISRC would settle it without any of this. The open API documents no
/// ISRC lookup; the Apple Music API has one and needs the paid developer
/// account. Until then, this is the rule.
enum CatalogMatch {
    struct Wanted: Equatable, Sendable {
        var title: String
        var artist: String
        /// Nil when the post carries no length. Title and artist then decide
        /// alone -- weaker -- and the first agreeing hit wins.
        var durationSeconds: Int?
    }

    /// Seconds. A remaster lands within one or two; a live take or a radio
    /// edit is usually much further out.
    static let durationTolerance = 3

    /// Whether two lengths could be the same recording. An unknown length on
    /// either side cannot contradict anything, so it agrees.
    static func lengthAgrees(_ length: Int?, with wanted: Int?) -> Bool {
        guard let length, let wanted else { return true }
        return abs(length - wanted) <= durationTolerance
    }

    static func best(for wanted: Wanted, among songs: [CatalogSong]) -> CatalogSong? {
        let title = normalized(wanted.title)
        let lead = leadArtist(of: wanted.artist)
        guard !title.isEmpty, !lead.isEmpty else { return nil }

        let agreeing = songs.filter {
            normalized($0.title) == title && contains(lead, in: normalized($0.artist))
        }
        guard let target = wanted.durationSeconds else { return agreeing.first }

        // Closest length wins; `min` keeps the first of equals, so ties go to
        // the catalog's own order.
        return agreeing
            .compactMap { song -> (song: CatalogSong, off: Int)? in
                guard let length = song.durationSeconds else { return nil }
                let off = abs(length - target)
                return off <= durationTolerance ? (song, off) : nil
            }
            .min { $0.off < $1.off }?
            .song
    }

    /// Words in a note that make it another recording, not another name for
    /// the same one. Measured: the iTunes search for "Blinding Lights The
    /// Weeknd" lists the ROSALÍA remix, the Major Lazer remix and the
    /// instrumental before the album cut.
    private static let versionWords = [
        "remix", "remixed", "rmx", "live", "acoustic", "unplugged", "instrumental",
        "sped up", "slowed", "karaoke", "cover", "demo", "acapella", "a cappella",
    ]

    /// Lowercased, accents folded, and stripped of what services disagree
    /// about: bracketed notes ("(feat. Khalid)", "[Remastered]"), trailing
    /// " - …" notes, and anything from "feat." on.
    ///
    /// A note that names a version stays, as its words: "Blinding Lights
    /// (Remix)" is "blinding lights remix", never "blinding lights" -- the
    /// remix is not the song. Spotify's "- Chromatics Remix" and the iTunes
    /// Store's "[Chromatics Remix]" still come out the same. A remaster or a
    /// radio edit is left to the length, as before.
    static func normalized(_ text: String) -> String {
        var t = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        var versions: [String] = []
        t = t.replacing(#/\(([^)]*)\)|\[([^\]]*)\]/#) { match in
            if let version = version(in: match.output.1 ?? match.output.2 ?? "") { versions.append(version) }
            return " "
        }
        if let dash = t.range(of: " - ") {
            // "Song - Live - 2011 Remaster" is two notes, not one.
            for note in t[dash.upperBound...].components(separatedBy: " - ") {
                if let version = version(in: note) { versions.append(version) }
            }
            t = String(t[..<dash.lowerBound])
        }
        // Only after a word: "Featuring You" is a title, not a credit, and
        // cutting from its first word left nothing to match on.
        t = t.replacingOccurrences(of: #"(?<=\S)\s+(feat|ft|featuring)\b.*$"#, with: " ", options: .regularExpression)
        // Sorted: which note a service writes first is spelling too.
        return (words(of: t) + versions.sorted()).joined(separator: " ")
    }

    /// A note's words if it names a version -- "major lazer remix", "live" --
    /// otherwise nil. A credit in it says who, not which: "(feat. Cover
    /// Drive)" is no cover. And "Acoustic Version" is just "acoustic".
    private static func version(in note: some StringProtocol) -> String? {
        let uncredited = String(note).replacing(#/(^|\s)(feat|ft|featuring|with)\b.*/#, with: "")
        let kept = words(of: uncredited).filter { $0 != "version" }.joined(separator: " ")
        guard versionWords.contains(where: { contains($0, in: kept) }) else { return nil }
        return kept
    }

    private static func words(of text: String) -> [String] {
        let kept = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").map(String.init)
    }

    /// The first named artist. Spotify writes "Post Malone, Swae Lee", the
    /// iTunes Store "Post Malone & Swae Lee"; the lead is what both agree on.
    static func leadArtist(of artists: String) -> String {
        let lowered = artists.lowercased()
        let lead = lowered
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first ?? lowered
        return normalized(lead)
    }

    /// Whole words only: "ocean" must not be found inside "oceans".
    private static func contains(_ needle: String, in haystack: String) -> Bool {
        (" " + haystack + " ").contains(" " + needle + " ")
    }
}
