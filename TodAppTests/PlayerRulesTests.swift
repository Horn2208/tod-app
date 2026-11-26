import Foundation
import Testing
@testable import TodApp

/// The rules under the full player view, checked without drawing it.
@Suite
struct PlayerRulesTests {
    private func roughly(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    // MARK: Cover

    /// Apple's catalog hands out a 100-pixel cover; its address names the
    /// size, and a bigger one is the same address with another number.
    @Test
    func anAppleCoverIsAskedForLarger() {
        let small = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/source/100x100bb.jpg")!

        #expect(ArtworkSize.large(small, side: 600)
            == URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/source/600x600bb.jpg")!)
    }

    /// MusicKit's cover already carries the size it was asked for.
    @Test
    func anyAppleSizeIsReplaced() {
        let kit = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/x/y/132x132bb.png")!

        #expect(ArtworkSize.large(kit, side: 600)?.lastPathComponent == "600x600bb.png")
    }

    /// Spotify's search and oEmbed hand out the 300-pixel cover; Home, which
    /// draws it full-screen, gets the 640 of the same image.
    @Test
    func aSmallSpotifyCoverIsAskedForLarger() {
        let small = URL(string: "https://i.scdn.co/image/ab67616d00001e02abc")!
        let post = Submission(
            id: 1, posterID: "p", track: "t", artist: "a", coverColorHex: "#000000", comments: [],
            source: TrackSource(service: .spotify, serviceTrackID: "x",
                                pageURL: URL(string: "https://open.spotify.com/track/x")!, artworkURL: small))

        #expect(post.coverURL == URL(string: "https://i.scdn.co/image/ab67616d0000b273abc")!)
    }

    /// A 640-pixel Spotify cover is already the large one.
    @Test
    func aCoverFromElsewhereIsLeftAlone() {
        let spotify = URL(string: "https://i.scdn.co/image/ab67616d0000b273abc")!

        #expect(ArtworkSize.large(spotify, side: 600) == spotify)
        #expect(ArtworkSize.large(nil, side: 600) == nil)
    }

    // MARK: Skipping

    @Test
    func aSkipMovesByFifteenSecondsInsideTheSong() {
        #expect(PlaybackSkip.target(position: 40, by: 15, duration: 200) == 55)
        #expect(PlaybackSkip.target(position: 40, by: -15, duration: 200) == 25)
    }

    /// Back near the start lands on the start; forward near the end stops a
    /// moment short, so the song does not end under the finger.
    @Test
    func aSkipStopsAtTheEnds() {
        #expect(PlaybackSkip.target(position: 5, by: -15, duration: 200) == 0)
        #expect(PlaybackSkip.target(position: 195, by: 15, duration: 200) == 199)
    }

    @Test
    func nothingToSkipWithoutALength() {
        #expect(PlaybackSkip.target(position: 0, by: 15, duration: 0) == nil)
    }

    // MARK: Waveform

    /// Before anything has played, the whole line is the quiet colour.
    @Test
    func anUnplayedWaveformIsAllQuiet() {
        #expect(WaveformFill.stops(progress: 0).map(\.isPlayed) == [false, false])
    }

    @Test
    func aFinishedWaveformIsAllLit() {
        #expect(WaveformFill.stops(progress: 1).map(\.isPlayed) == [true, true])
    }

    /// No hard edge: the lit part fades into the rest over a short stretch
    /// around the playhead.
    @Test
    func thePlayheadIsASoftEdge() {
        let stops = WaveformFill.stops(progress: 0.5, softness: 0.05)

        #expect(stops.map(\.isPlayed) == [true, true, false, false])
        #expect(roughly(stops.map(\.location), [0, 0.45, 0.55, 1]))
    }

    @Test
    func theSoftEdgeStaysInsideTheLine() {
        let early = WaveformFill.stops(progress: 0.02, softness: 0.05)

        #expect(roughly(early.map(\.location), [0, 0, 0.07, 1]))
    }

    // MARK: Whole song in Spotify

    private let premium = MusicProviderCapabilities(
        canSearch: true, canPlayFullTracks: true, canStartAtPosition: true, playsInsideTheApp: false)

    /// Only a Spotify post, and only for a connected account Spotify lets
    /// start a song at a position -- Premium.
    @Test
    func theWholeSongInSpotifyIsOfferedToPremiumOnSpotifyPosts() {
        #expect(SpotifyWholeSong.offers(service: .spotify, capabilities: premium))
        #expect(!SpotifyWholeSong.offers(service: .spotify, capabilities: .none))
        #expect(!SpotifyWholeSong.offers(service: nil, capabilities: premium))
        #expect(!SpotifyWholeSong.offers(service: .soundcloud, capabilities: premium))
    }

    /// Premium and the Spotify app: the play button itself goes to Spotify,
    /// whatever would play here otherwise -- Apple's preview or the embed.
    @Test
    func playGoesToSpotifyForPremiumWithTheApp() {
        for route: TrackPlayerSheet.Player in [.applePreview, .own, .waiting] {
            #expect(SpotifyWholeSong.startsOnPlay(
                offers: true, isAppInstalled: true, appleMusicWholeSongs: false, route: route))
        }
    }

    @Test
    func playStaysHereWithoutPremiumOrTheApp() {
        #expect(!SpotifyWholeSong.startsOnPlay(
            offers: false, isAppInstalled: true, appleMusicWholeSongs: false, route: .own))
        // Without the app the press would open a web page instead of playing.
        #expect(!SpotifyWholeSong.startsOnPlay(
            offers: true, isAppInstalled: false, appleMusicWholeSongs: false, route: .own))
    }

    /// Apple Music plays the whole song in this app from the section; that
    /// stays first, and so does waiting to learn whether it can.
    @Test
    func appleMusicsWholeSongStaysFirst() {
        #expect(!SpotifyWholeSong.startsOnPlay(
            offers: true, isAppInstalled: true, appleMusicWholeSongs: true, route: .appleMusic))
        #expect(!SpotifyWholeSong.startsOnPlay(
            offers: true, isAppInstalled: true, appleMusicWholeSongs: true, route: .waiting))
        #expect(SpotifyWholeSong.startsOnPlay(
            offers: true, isAppInstalled: true, appleMusicWholeSongs: true, route: .own))
    }

    /// "Spotify öffnen" opens the Spotify app on the song itself, so even
    /// when the start does not come through, the listener lands on it.
    @Test
    func spotifyOpensOnTheSong() {
        let source = TrackSource(
            service: .spotify, serviceTrackID: "51KP8yo3FnpKJtrQIsriu4",
            pageURL: URL(string: "https://open.spotify.com/track/51KP8yo3FnpKJtrQIsriu4")!)

        #expect(SpotifyWholeSong.appURL(for: source) == URL(string: "spotify:track:51KP8yo3FnpKJtrQIsriu4"))
    }

    // MARK: Scrubbing

    /// A finger dragging along the waveform feels each five seconds it
    /// crosses -- the same steps VoiceOver moves by.
    @Test
    func scrubbingTicksEveryFiveSeconds() {
        #expect(ScrubTick.step(fraction: 0, duration: 200) == 0)
        #expect(ScrubTick.step(fraction: 0.024, duration: 200) == 0)   // 4.8 s
        #expect(ScrubTick.step(fraction: 0.026, duration: 200) == 1)   // 5.2 s
        #expect(ScrubTick.step(fraction: 1, duration: 200) == 40)
        #expect(ScrubTick.step(fraction: 0.5, duration: 0) == nil)
    }

    // MARK: Hints

    /// On screen a short line; the full explanation behind the (i).
    @Test
    func aHintIsShortOnScreenAndFullBehindTheButton() {
        let preview = PlayerHint.applePreview(sectionStart: 67)
        #expect(preview.short == "Vorschau · 30 s")
        #expect(preview.detail.contains("ab 1:07"))

        let excerpt = PlayerHint.spotifyExcerpt(sectionStart: 70)
        #expect(excerpt.short == "Vorschau · 30 s · ohne 1:10")
        #expect(excerpt.detail.contains("Spotify öffnen"))

        #expect(PlayerHint.widgetFromStart.short == "Spielt von Anfang an")
    }

    /// The short line fits one row: no explanation creeps back into it.
    @Test
    func theShortLineStaysShort() {
        for hint in [PlayerHint.applePreview(sectionStart: 600), .spotifyExcerpt(sectionStart: 600), .widgetFromStart] {
            #expect(hint.short.count <= 32)
        }
    }

    // MARK: Platforms

    @Test
    func aSpotifyPostFoundInAppleOffersBoth() {
        let links = PlatformLinks.links(
            service: .spotify,
            servicePage: URL(string: "https://open.spotify.com/track/abc"),
            appleMusicPage: URL(string: "https://music.apple.com/de/album/x?i=1"))

        #expect(links.map(\.label) == ["Music öffnen", "Spotify öffnen"])
        #expect(links.map(\.kind) == [.appleMusic, .spotify])
    }

    @Test
    func aPostWithoutLinkOffersOnlyApple() {
        let links = PlatformLinks.links(
            service: nil, servicePage: nil,
            appleMusicPage: URL(string: "https://music.apple.com/de/album/x?i=1"))

        #expect(links.map(\.label) == ["Music öffnen"])
    }

    @Test
    func aSoundCloudPostOffersSoundCloud() {
        let links = PlatformLinks.links(
            service: .soundcloud, servicePage: URL(string: "https://soundcloud.com/a/b"),
            appleMusicPage: nil)

        #expect(links.map(\.label) == ["SoundCloud öffnen"])
    }

    @Test
    func nothingKnownOffersNothing() {
        #expect(PlatformLinks.links(service: nil, servicePage: nil, appleMusicPage: nil).isEmpty)
    }
}
