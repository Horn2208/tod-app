import Foundation
import Testing
@testable import TodApp

/// The result lists here are real: what the iTunes Search API (storefront
/// "de") answered on 11 September 2026.
@Suite
struct CatalogMatchTests {
    private func song(_ id: Int, _ title: String, _ artist: String, _ seconds: Int?) -> CatalogSong {
        CatalogSong(id: String(id), title: title, artist: artist, durationSeconds: seconds)
    }

    /// "Nights Frank Ocean", limit 10. The song asked for is not in it.
    private var nightsHits: [CatalogSong] {
        [
            song(1146195726, "Seigfried", "Frank Ocean", 334),
            song(1146195725, "White Ferrari", "Frank Ocean", 248),
            song(1146195714, "Pink + White", "Frank Ocean", 184),
            song(1445729383, "Swim Good", "Frank Ocean", 257),
            song(1146195718, "Self Control", "Frank Ocean", 249),
            song(1146195727, "Godspeed", "Frank Ocean", 177),
            song(1849691527, "Frank Ocean", "Magdalena Wawra & Malvin", 198),
            song(1460193258, "Ocean", "KAROL G", 153),
            song(1397556695, "Ocean (feat. Khalid)", "Martin Garrix", 216),
            song(408373191, "Nights (Feel Like Gettin' Down)", "Billy Ocean", 282),
        ]
    }

    @Test
    func picksTheSongAmongItsSeveralReleases() {
        let hits = [
            song(1499386265, "Blinding Lights", "The Weeknd", 200),
            song(1505683988, "Blinding Lights", "The Weeknd", 200),
            song(1499378607, "Blinding Lights", "The Weeknd", 200),
        ]
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

        #expect(CatalogMatch.best(for: wanted, among: hits)?.id == "1499386265")
    }

    /// The whole reason the rule exists: none of these is "Nights", and a
    /// first-hit rule would have played Martin Garrix.
    @Test
    func aListWithoutTheSongGivesNoMatch() {
        let wanted = CatalogMatch.Wanted(title: "Nights", artist: "Frank Ocean", durationSeconds: 307)

        #expect(CatalogMatch.best(for: wanted, among: nightsHits) == nil)
    }

    /// Billy Ocean's "Nights (Feel Like Gettin' Down)" has the same title once
    /// the brackets go. The artist has to catch it when no length is known.
    @Test
    func theArtistCatchesATitleTwinWithoutALength() {
        let wanted = CatalogMatch.Wanted(title: "Nights", artist: "Frank Ocean", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: nightsHits) == nil)
    }

    @Test
    func aDifferentLengthIsADifferentRecording() {
        let live = [song(1, "Blinding Lights", "The Weeknd", 240)]
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

        #expect(CatalogMatch.best(for: wanted, among: live) == nil)
    }

    @Test
    func theToleranceIsThreeSeconds() {
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Blinding Lights", "The Weeknd", 203)]) != nil)
        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Blinding Lights", "The Weeknd", 204)]) == nil)
    }

    @Test
    func theClosestLengthWins() {
        let hits = [
            song(1, "Blinding Lights", "The Weeknd", 203),
            song(2, "Blinding Lights", "The Weeknd", 201),
        ]
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

        #expect(CatalogMatch.best(for: wanted, among: hits)?.id == "2")
    }

    /// How the two services write the same song differently.
    @Test
    func servicesMayDisagreeOnSpellingButNotOnTheSong() {
        let hit = [song(1, "Sunflower (Spider-Man: Into the Spider-Verse)", "Post Malone & Swae Lee", 158)]
        let wanted = CatalogMatch.Wanted(
            title: "Sunflower - Spider-Man: Into the Spider-Verse",
            artist: "Post Malone, Swae Lee",
            durationSeconds: 158)

        #expect(CatalogMatch.best(for: wanted, among: hit)?.id == "1")
    }

    @Test
    func accentsDoNotMatter() {
        let hit = [song(1, "Déjà Vu", "Beyoncé", 240)]
        let wanted = CatalogMatch.Wanted(title: "Deja Vu", artist: "Beyonce", durationSeconds: 240)

        #expect(CatalogMatch.best(for: wanted, among: hit) != nil)
    }

    /// A link posted without metadata has no title to match on.
    @Test
    func noTitleNoMatch() {
        let wanted = CatalogMatch.Wanted(title: "", artist: "", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Blinding Lights", "The Weeknd", 200)]) == nil)
    }
}
