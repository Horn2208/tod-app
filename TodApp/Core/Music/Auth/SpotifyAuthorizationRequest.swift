import Foundation

/// The URL the sign-in sheet opens, and the reading of what comes back.
/// Pure and offline, so every odd callback shape belongs in the test table.
struct SpotifyAuthorizationRequest {
    static let scopes = [
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state"
    ]

    let clientID: String
    let redirectURI: String
    let verifier: String
    let state: String

    var url: URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier))
        ]
        return components.url!
    }

    static func code(from callback: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw TodAppError.authorizationFailed
        }
        let items = Dictionary(
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Check state first, for every path: a callback we did not start has nothing
        // worth reading out of it. RFC 6749 §4.1.2.1 requires the authorization server
        // to echo `state` in both success and error responses when the request carried one.
        guard items["state"] == expectedState else {
            throw TodAppError.authorizationFailed
        }

        if let error = items["error"] {
            // Declining is the one "error" that is really a choice.
            throw error == "access_denied"
                ? TodAppError.authorizationCancelled
                : TodAppError.authorizationFailed
        }

        guard let code = items["code"] else {
            throw TodAppError.authorizationFailed
        }
        return code
    }
}
