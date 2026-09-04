import Foundation

enum TodAppError: Error, Equatable {
    case notFound
    case alreadyVoted
    case network(underlying: Error)
    /// Spotify search is unusable until Secrets.xcconfig is filled in.
    case missingSpotifyCredentials
    case rateLimited
    case linkNotRecognised
    case trackUnavailable
    /// The search service itself is not answering properly. Distinct from
    /// `missingSpotifyCredentials`, whose message tells the user to fill in
    /// Secrets.xcconfig -- nonsense once a proxy holds the secret and the app
    /// ships without one.
    case searchUnavailable

    static func == (lhs: TodAppError, rhs: TodAppError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound), (.alreadyVoted, .alreadyVoted),
             (.missingSpotifyCredentials, .missingSpotifyCredentials),
             (.rateLimited, .rateLimited), (.linkNotRecognised, .linkNotRecognised),
             (.trackUnavailable, .trackUnavailable),
             (.searchUnavailable, .searchUnavailable):
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
