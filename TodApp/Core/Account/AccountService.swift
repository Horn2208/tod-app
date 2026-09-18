import Foundation

/// Who is using the app. The id is the backend's user id -- or, in a build
/// without a backend, the local stand-in the in-memory data is written for.
struct AccountUser: Equatable, Sendable {
    let id: String
}

/// Signing in and out of the app itself.
///
/// Separate from the music services on purpose: an account is who you are in
/// your groups, Spotify is only one way to find and hear songs. Before this
/// existed, "signed in" meant "Spotify connected", and there was no way into
/// the app without Spotify.
protocol AccountService: Sendable {
    /// The account a previous launch left signed in, if it is still valid.
    func restore() async -> AccountUser?
    /// Signs in with the identity token Sign in with Apple handed over, and
    /// the unhashed nonce whose hash went into that request. `name` arrives
    /// from Apple on the very first sign-in only; it becomes the profile name.
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser
    func signOut() async
#if DEBUG
    /// An account without Apple, for trying the app in the simulator, which
    /// has no Apple Account. Debug builds only; the project must allow
    /// anonymous sign-ins.
    func signInAnonymously() async throws -> AccountUser
#endif
}

#if DEBUG
extension AccountService {
    func signInAnonymously() async throws -> AccountUser {
        throw TodAppError.accountSignInFailed
    }
}
#endif

/// A build without a backend (`SupabaseConfig` missing), and the tests: always
/// the local user of the in-memory data, so the app runs as it did before
/// accounts existed.
struct LocalAccountService: AccountService {
    static let user = AccountUser(id: "du")

    func restore() async -> AccountUser? { Self.user }

    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
        Self.user
    }

    func signOut() async {}
}
