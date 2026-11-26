import Foundation

/// Who is using the app. The id is the backend's user id -- or, in a build
/// without a backend, the local stand-in the in-memory data is written for.
struct AccountUser: Equatable, Sendable {
    let id: String
    /// Made with "Ohne Anmeldung": nothing to sign in with again, so the
    /// account lives on this phone only.
    var isAnonymous = false
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
    /// Signs in with Spotify: the Spotify account makes the app account, and
    /// the same Spotify session serves the player afterwards.
    func signInWithSpotify() async throws -> AccountUser
    /// An account without anything to sign in with ("Ohne Anmeldung"). It
    /// works like any other, but only on this phone: signed out, or the app
    /// deleted, and there is no way back into it.
    func signInAnonymously() async throws -> AccountUser
    func signOut() async
    /// Gives an account made without sign-in an Apple ID to come back with:
    /// same account, same groups, now found again on any phone.
    func linkApple(idToken: String, nonce: String) async throws -> AccountUser
    /// Deletes the account on the server, and everything that is only its
    /// own, then signs out on this phone. Throws when the server did not.
    func deleteAccount() async throws
}

/// For stand-ins that only play one part: a way in they do not offer fails
/// like a refused sign-in.
extension AccountService {
    func signInWithSpotify() async throws -> AccountUser {
        throw TodAppError.accountSignInFailed
    }

    func signInAnonymously() async throws -> AccountUser {
        throw TodAppError.accountSignInFailed
    }

    func deleteAccount() async throws {
        throw TodAppError.notAllowed
    }

    func linkApple(idToken: String, nonce: String) async throws -> AccountUser {
        throw TodAppError.notAllowed
    }
}

/// A build without a backend (`SupabaseConfig` missing), and the tests: always
/// the local user of the in-memory data, so the app runs as it did before
/// accounts existed.
struct LocalAccountService: AccountService {
    static let user = AccountUser(id: "du")

    /// Nothing on a server to delete.
    func deleteAccount() async throws {}

    func restore() async -> AccountUser? { Self.user }

    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
        Self.user
    }

    func signInWithSpotify() async throws -> AccountUser { Self.user }

    func signInAnonymously() async throws -> AccountUser { Self.user }

    func linkApple(idToken: String, nonce: String) async throws -> AccountUser { Self.user }

    func signOut() async {}
}
