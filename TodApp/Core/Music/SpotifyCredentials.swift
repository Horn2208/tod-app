import Foundation

struct SpotifyCredentials: Sendable {
    let clientID: String
    let clientSecret: String

    /// Takes the lookup as a closure rather than a Bundle: Bundle has no
    /// accessible designated initialiser, so it cannot be stubbed in a test.
    static func from(infoValueForKey lookup: (String) -> Any?) throws -> SpotifyCredentials {
        let id = lookup("SpotifyClientID") as? String ?? ""
        let secret = lookup("SpotifyClientSecret") as? String ?? ""
        guard !id.isEmpty, !secret.isEmpty else {
            throw TodAppError.missingSpotifyCredentials
        }
        return SpotifyCredentials(clientID: id, clientSecret: secret)
    }

    static func fromBundle(_ bundle: Bundle = .main) throws -> SpotifyCredentials {
        try from(infoValueForKey: { bundle.object(forInfoDictionaryKey: $0) })
    }
}
