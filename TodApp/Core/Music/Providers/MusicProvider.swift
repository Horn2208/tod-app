import Foundation

/// What a provider can do. Partly fixed, partly only known after signing in --
/// whether full tracks play depends on the subscription behind the account.
struct MusicProviderCapabilities: Equatable, Sendable {
    /// Whether the provider supports searching for tracks by query.
    var canSearch: Bool
    /// Whether the provider can play full tracks on this account's subscription.
    /// Distinguished from `canStartAtPosition`: this flag alone means "may be told to play",
    /// while `canStartAtPosition` additionally permits starting at a specific position.
    var canPlayFullTracks: Bool
    /// Whether the provider can be told to start playing from a specific position within a track.
    /// Always false if `canPlayFullTracks` is false.
    var canStartAtPosition: Bool
    /// Whether the sound comes out of this app or out of the service's own.
    var playsInsideTheApp: Bool

    /// What a provider claims before anyone has signed in.
    static let none = MusicProviderCapabilities(
        canSearch: false, canPlayFullTracks: false,
        canStartAtPosition: false, playsInsideTheApp: false
    )
}

/// One music service, behind one door. Views ask what a provider *can do*,
/// never who it is -- otherwise `if service == .spotify` grows through every
/// screen, and Apple Music, which speaks no OAuth and brings its own player,
/// fits nowhere later.
protocol MusicProvider: Sendable {
    nonisolated var service: MusicService { get }
    var isAuthorized: Bool { get async }
    /// Only meaningful once `authorize()` has returned.
    var capabilities: MusicProviderCapabilities { get async }

    func authorize() async throws
    /// Brings a stored session back without asking again. A provider with
    /// nothing stored simply stays signed out.
    func restore() async
    func signOut() async

    func searchTracks(matching query: String) async throws -> [TrackCandidate]
    /// `section == nil` means from the beginning. With `stopsAtSectionEnd`
    /// playback ends where the section does; without, the whole song plays on
    /// from the section's start.
    func play(_ source: TrackSource, from section: TrackSection?, stopsAtSectionEnd: Bool) async throws
    func stop() async

    /// The track currently playing, republished every time playback genuinely
    /// starts or stops -- including a stop the provider decides on its own
    /// (an end-of-section timer), not only one requested through `stop()`.
    /// `nil` means nothing is playing.
    ///
    /// A consumer reads this instead of keeping its own play/stop flag: only
    /// the provider knows when its own timer fires, so a second, view-local
    /// clock for the same event would drift out of sync with it.
    func playbackUpdates() async -> AsyncStream<TrackSource?>
}

extension MusicProvider {
    /// Plays just the section.
    func play(_ source: TrackSource, from section: TrackSection?) async throws {
        try await play(source, from: section, stopsAtSectionEnd: true)
    }
}
