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

    static func == (lhs: TodAppError, rhs: TodAppError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound), (.alreadyVoted, .alreadyVoted),
             (.missingSpotifyCredentials, .missingSpotifyCredentials),
             (.rateLimited, .rateLimited), (.linkNotRecognised, .linkNotRecognised),
             (.trackUnavailable, .trackUnavailable):
            return true
        case let (.network(l), .network(r)):
            return (l as NSError) == (r as NSError)
        default:
            return false
        }
    }
}
