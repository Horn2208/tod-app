import Foundation
import Testing
@testable import TodApp

/// A second provider that is not Spotify. Its only job is to prove that
/// nothing outside a provider branches on `MusicService`.
actor FakeMusicProvider: MusicProvider {
    nonisolated let service: MusicService = .soundcloud

    private var authorized = false
    private var declaredCapabilities: MusicProviderCapabilities
    private(set) var playedSource: TrackSource?
    private(set) var playedSection: TrackSection?

    init(capabilities: MusicProviderCapabilities) {
        self.declaredCapabilities = capabilities
    }

    var isAuthorized: Bool { authorized }
    var capabilities: MusicProviderCapabilities { declaredCapabilities }

    func authorize() async throws { authorized = true }
    func restore() async {}
    func signOut() async { authorized = false }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        guard declaredCapabilities.canSearch else { throw TodAppError.searchUnavailable }
        return []
    }

    func play(_ source: TrackSource, from section: TrackSection?) async throws {
        guard declaredCapabilities.canPlayFullTracks else {
            throw TodAppError.playbackNotAvailable
        }
        playedSource = source
        playedSection = section
    }

    func stop() async {}
}

@Suite
struct MusicProviderTests {
    private let source = TrackSource(
        service: .soundcloud,
        serviceTrackID: "https://soundcloud.com/a/b",
        pageURL: URL(string: "https://soundcloud.com/a/b")!,
        artworkURL: nil
    )

    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: true
        )
    }

    private var nothing: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: false, canPlayFullTracks: false,
            canStartAtPosition: false, playsInsideTheApp: false
        )
    }

    @Test
    func aProviderStartsSignedOut() async {
        #expect(await FakeMusicProvider(capabilities: everything).isAuthorized == false)
    }

    @Test
    func authorizingThenSigningOutRoundTrips() async throws {
        let provider = FakeMusicProvider(capabilities: everything)

        try await provider.authorize()
        #expect(await provider.isAuthorized)

        await provider.signOut()
        #expect(await provider.isAuthorized == false)
    }

    /// A provider that cannot play says so by throwing, not by pretending.
    @Test
    func aProviderWithoutPlaybackRefusesToPlay() async {
        let provider = FakeMusicProvider(capabilities: nothing)

        await #expect(throws: TodAppError.playbackNotAvailable) {
            try await provider.play(source, from: nil)
        }
    }

    @Test
    func aSectionIsHandedToTheProviderUnchanged() async throws {
        let provider = FakeMusicProvider(capabilities: everything)

        try await provider.play(source, from: TrackSection(start: 82, end: 112))

        #expect(await provider.playedSection == TrackSection(start: 82, end: 112))
    }
}
