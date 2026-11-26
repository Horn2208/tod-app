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
    /// The credit is cut only where it follows the title. A title that begins
    /// with the word used to normalize to nothing -- which the matcher then
    /// refused as no title at all.
    @Test
    func aTitleThatBeginsWithFeaturingIsKept() {
        #expect(CatalogMatch.normalized("Featuring You") == "featuring you")

        let wanted = CatalogMatch.Wanted(title: "Featuring You", artist: "Someone", durationSeconds: 180)
        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Featuring You", "Someone", 180)])?.id == "1")
    }

    @Test
    func aTrailingCreditIsStillCut() {
        #expect(CatalogMatch.normalized("Sunflower feat. Swae Lee") == "sunflower")
        #expect(CatalogMatch.normalized("Sunflower ft. Swae Lee") == "sunflower")
    }

    /// An unknown length on either side cannot contradict anything.
    @Test
    func lengthsAgreeWithinTheToleranceOrWhenOneIsUnknown() {
        #expect(CatalogMatch.lengthAgrees(203, with: 200))
        #expect(!CatalogMatch.lengthAgrees(204, with: 200))
        #expect(CatalogMatch.lengthAgrees(nil, with: 200))
        #expect(CatalogMatch.lengthAgrees(170, with: nil))
    }

    /// "Blinding Lights The Weeknd", limit 25, asked on 16 September 2026;
    /// the first twelve. Four versions of the song come before the song.
    private var blindingLightsHits: [CatalogSong] {
        [
            song(1542842761, "Blinding Lights (Remix)", "The Weeknd & ROSALÍA", 216),
            song(1508046220, "Blinding Lights (Major Lazer Remix) [feat. Major Lazer]", "The Weeknd", 197),
            song(1531551391, "Blinding Lights (Instrumental)", "The Weeknd", 202),
            song(1687577044, "Blinding Lights The Weeknd", "Pancadão GD Som", 185),
            song(1499386265, "Blinding Lights", "The Weeknd", 200),
            song(1505683988, "Blinding Lights", "The Weeknd", 200),
            song(1499378607, "Blinding Lights", "The Weeknd", 200),
            song(1505682603, "Blinding Lights (feat. Chromatics) [Chromatics Remix]", "The Weeknd", 261),
            song(1505683967, "Blinding Lights", "The Weeknd", 200),
            song(1676308593, "Blinding Lights (Live)", "The Weeknd", 253),
            song(1729919128, "Blinding Lights", "The Weeknd", 200),
            song(1770305192, "Blinding Lights (David Garrett Edition)", "David Garrett", 226),
        ]
    }

    /// Seen in the simulator: the seeded post, which has no length, played
    /// the ROSALÍA remix -- the first hit once "(Remix)" was thrown away.
    @Test
    func withoutALengthTheSongIsNotItsRemix() {
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: blindingLightsHits)?.id == "1499386265")
    }

    @Test
    func aRemixIsFoundAsTheRemix() {
        let hits = [
            song(1, "Blinding Lights", "The Weeknd", 200),
            song(2, "Blinding Lights (Remix)", "The Weeknd & ROSALÍA", 216),
        ]
        // How Spotify writes it: the partner as a credit, the version after a dash.
        let wanted = CatalogMatch.Wanted(
            title: "Blinding Lights (with ROSALÍA) - Remix", artist: "The Weeknd, ROSALÍA", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: hits)?.id == "2")
    }

    /// Whose remix it is belongs to the version, however each service
    /// writes it down.
    @Test
    func oneRemixIsNotAnother() {
        let lazer = CatalogMatch.Wanted(
            title: "Blinding Lights - Major Lazer Remix", artist: "The Weeknd", durationSeconds: nil)
        let chromatics = CatalogMatch.Wanted(
            title: "Blinding Lights (feat. Chromatics) - Chromatics Remix", artist: "The Weeknd", durationSeconds: nil)

        #expect(CatalogMatch.best(for: lazer, among: blindingLightsHits)?.id == "1508046220")
        #expect(CatalogMatch.best(for: chromatics, among: blindingLightsHits)?.id == "1505682603")
    }

    @Test
    func aLiveTakeIsFoundAsTheLiveTake() {
        let wanted = CatalogMatch.Wanted(title: "Blinding Lights - Live", artist: "The Weeknd", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: blindingLightsHits)?.id == "1676308593")
    }

    /// The other way round: a live take asked for, and only the album cut
    /// there. No match beats the wrong recording.
    @Test
    func aVersionDoesNotSettleForTheOriginal() {
        let hits = [song(1, "Blinding Lights", "The Weeknd", 200)]

        for title in ["Blinding Lights (Live)", "Blinding Lights - Acoustic", "Blinding Lights [Instrumental]",
                      "Blinding Lights - Sped Up", "Blinding Lights (Slowed + Reverb)", "Blinding Lights (Karaoke)",
                      "Blinding Lights (Cover)"] {
            let wanted = CatalogMatch.Wanted(title: title, artist: "The Weeknd", durationSeconds: nil)
            #expect(CatalogMatch.best(for: wanted, among: hits) == nil, "\(title)")
        }
    }

    /// Notes about the same recording are still thrown away.
    @Test
    func aRemasterIsTheSameRecording() {
        let wanted = CatalogMatch.Wanted(title: "Nights - Remastered", artist: "Frank Ocean", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Nights", "Frank Ocean", 307)])?.id == "1")
        #expect(CatalogMatch.normalized("Nights (Remastered 2016)") == "nights")
        #expect(CatalogMatch.normalized("Nights - Radio Edit") == "nights")
    }

    @Test
    func aVersionIsKeptHoweverItIsWritten() {
        #expect(CatalogMatch.normalized("Blinding Lights (Remix)") == "blinding lights remix")
        #expect(CatalogMatch.normalized("Song - Sped Up Version") == CatalogMatch.normalized("Song (Sped Up)"))
        #expect(CatalogMatch.normalized("Song - Live - 2011 Remaster") == CatalogMatch.normalized("Song (Live) [2011 Remaster]"))
    }

    /// A credit says who, not which: an artist called "Cover Drive" does not
    /// make a cover.
    @Test
    func aCreditInsideANoteIsNoVersion() {
        #expect(CatalogMatch.normalized("Song (feat. Cover Drive)") == "song")
        #expect(CatalogMatch.normalized("Song [with Live Wire]") == "song")
    }

    /// Only a note can name a version. In the title itself, the word is the title.
    @Test
    func aVersionWordInTheTitleIsJustTheTitle() {
        let wanted = CatalogMatch.Wanted(title: "Live Forever", artist: "Oasis", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Live Forever", "Oasis", 276)])?.id == "1")
    }

    @Test
    func noTitleNoMatch() {
        let wanted = CatalogMatch.Wanted(title: "", artist: "", durationSeconds: nil)

        #expect(CatalogMatch.best(for: wanted, among: [song(1, "Blinding Lights", "The Weeknd", 200)]) == nil)
    }
}
