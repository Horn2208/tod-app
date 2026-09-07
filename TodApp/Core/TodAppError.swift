import Foundation

enum TodAppError: Error, Equatable {
    case notFound
    case alreadyVoted
    case network(underlying: Error)
    case rateLimited
    case trackUnavailable
    /// The search service itself is not answering properly -- a server-side
    /// problem, distinct from a rejected session, and nothing the person
    /// searching can act on.
    case searchUnavailable
    /// The redirect came back wrong: no code, or a state we did not send.
    case authorizationFailed
    /// The person declined, or dismissed the sheet. Not an error to report.
    case authorizationCancelled
    /// Reading or writing the stored token failed. A storage problem, not a
    /// sign-in problem -- the distinction matters to whoever reads the message.
    case tokenStorageFailed
    /// Spotify has nowhere to play: no device of this account is active.
    case noActivePlaybackDevice
    /// This account cannot be told to play -- a free tier, in Spotify's case.
    case playbackNotAvailable
    /// A `TrackSource` from a different service was handed to a provider's
    /// `play(_:from:)` -- a SoundCloud link reaching Spotify, say. Caught
    /// before any request goes out, so this never becomes a rejected request
    /// a provider could otherwise misreport as having succeeded.
    case sourceFromAnotherService

    static func == (lhs: TodAppError, rhs: TodAppError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound), (.alreadyVoted, .alreadyVoted),
             (.rateLimited, .rateLimited),
             (.trackUnavailable, .trackUnavailable),
             (.searchUnavailable, .searchUnavailable),
             (.authorizationFailed, .authorizationFailed),
             (.authorizationCancelled, .authorizationCancelled),
             (.tokenStorageFailed, .tokenStorageFailed),
             (.noActivePlaybackDevice, .noActivePlaybackDevice),
             (.playbackNotAvailable, .playbackNotAvailable),
             (.sourceFromAnotherService, .sourceFromAnotherService):
            return true
        case (.network, .network):
            // Bridging an arbitrary `Error` to `NSError` compares case identity
            // (domain from the concrete type, code from the enum ordinal), not
            // the payload -- `userInfo` is empty unless the type adopts
            // `CustomNSError`. So two genuinely different underlying failures
            // would compare equal, which is a worse outcome than admitting we
            // cannot compare them. `.network` is therefore deliberately never
            // equal to anything, even to another `.network` wrapping the same
            // error.
            return false
        default:
            return false
        }
    }
}
