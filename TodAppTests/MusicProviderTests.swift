import Foundation
import Testing
@testable import TodApp

/// A second provider that is not Spotify. Its only job is to prove that
/// nothing outside a provider branches on `MusicService`.
actor FakeMusicProvider: MusicProvider {
    nonisolated let service: MusicService = .soundcloud

    private var authorized = false
    private var declaredCapabilities: MusicProviderCapabilities
    /// Lets a test control exactly what a search returns or throws -- canned
    /// results, a specific error, or a gate that holds the call open until
    /// the test releases it to force a real race between two overlapping
    /// searches. Defaults to "no results", so a test that only cares whether
    /// search is reachable at all (the `canSearch` gate below) needs nothing
    /// extra.
    private let search: @Sendable (String) async throws -> [TrackCandidate]
    private(set) var playedSource: TrackSource?
    private(set) var playedSection: TrackSection?
    private var currentlyPlaying: TrackSource?
    private var playbackContinuation: AsyncStream<TrackSource?>.Continuation?

    init(
        capabilities: MusicProviderCapabilities,
        search: @escaping @Sendable (String) async throws -> [TrackCandidate] = { _ in [] }
    ) {
        self.declaredCapabilities = capabilities
        self.search = search
    }

    var isAuthorized: Bool { authorized }
    var capabilities: MusicProviderCapabilities {
        authorized ? declaredCapabilities : .none
    }

    func authorize() async throws { authorized = true }
    func restore() async {}
    func signOut() async { authorized = false }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        guard declaredCapabilities.canSearch else { throw TodAppError.searchUnavailable }
        return try await search(query)
    }

    func play(_ source: TrackSource, from section: TrackSection?, stopsAtSectionEnd: Bool) async throws {
        guard declaredCapabilities.canPlayFullTracks else {
            throw TodAppError.playbackNotAvailable
        }
        playedSource = source
        playedSection = section
        setCurrentlyPlaying(source)
    }

    func stop() async {
        setCurrentlyPlaying(nil)
    }

    func playbackUpdates() async -> AsyncStream<TrackSource?> {
        AsyncStream { continuation in
            playbackContinuation = continuation
            continuation.yield(currentlyPlaying)
        }
    }

    private func setCurrentlyPlaying(_ track: TrackSource?) {
        guard track != currentlyPlaying else { return }
        currentlyPlaying = track
        playbackContinuation?.yield(track)
    }
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

    /// Finding 2: A freshly constructed provider reports `.none` even though
    /// it was constructed with full capabilities, and the constructed
    /// capabilities appear only after `authorize()`.
    @Test
    func aFreshProviderReportsNoCapabilitiesBeforeAuthorization() async throws {
        let provider = FakeMusicProvider(capabilities: everything)

        #expect(await provider.capabilities == .none)

        try await provider.authorize()

        #expect(await provider.capabilities == everything)
    }

    /// Finding 2: `signOut()` must return capabilities to `.none`.
    @Test
    func signingOutReturnsCapabilitiesToNone() async throws {
        let provider = FakeMusicProvider(capabilities: everything)

        try await provider.authorize()
        #expect(await provider.capabilities == everything)

        await provider.signOut()
        #expect(await provider.capabilities == .none)
    }

    /// Finding 2: `restore()` must not grant capabilities on its own.
    @Test
    func restoringDoesNotGrantCapabilities() async {
        let provider = FakeMusicProvider(capabilities: everything)

        await provider.restore()

        #expect(await provider.capabilities == .none)
    }

    /// Finding 1: `restore()` on a provider with nothing stored leaves it signed out.
    @Test
    func restoringAProviderWithNothingStoredLeavesItSignedOut() async {
        let provider = FakeMusicProvider(capabilities: everything)

        await provider.restore()

        #expect(await provider.isAuthorized == false)
    }

    /// Finding 1: `searchTracks(matching:)` on a provider whose capabilities
    /// have `canSearch == false` throws `TodAppError.searchUnavailable`.
    @Test
    func aProviderWithoutSearchRefusesToSearch() async {
        let provider = FakeMusicProvider(capabilities: nothing)

        await #expect(throws: TodAppError.searchUnavailable) {
            try await provider.searchTracks(matching: "test")
        }
    }

    /// Finding 1: `searchTracks(matching:)` on a provider with `canSearch == true`
    /// returns without throwing.
    @Test
    func aProviderWithSearchCanSearchWithoutThrowing() async throws {
        let provider = FakeMusicProvider(capabilities: everything)

        try await provider.authorize()

        let results = try await provider.searchTracks(matching: "test")
        #expect(results.isEmpty)
    }

}
