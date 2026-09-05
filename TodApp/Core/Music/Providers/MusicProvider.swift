import Foundation

/// What a provider can do. Partly fixed, partly only known after signing in --
/// whether full tracks play depends on the subscription behind the account.
struct MusicProviderCapabilities: Equatable, Sendable {
    var canSearch: Bool
    var canPlayFullTracks: Bool
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
    /// `section == nil` means from the beginning.
    func play(_ source: TrackSource, from section: TrackSection?) async throws
    func stop() async
}
