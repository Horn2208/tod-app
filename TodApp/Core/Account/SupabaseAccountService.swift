import Foundation
import Supabase
import os

extension SupabaseConfig {
    /// The one client for this project. The session it signs in with is kept
    /// in the Keychain by the library and refreshed by it.
    func makeClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                // The library's coming default, taken now: a stored session is
                // reported as it is, and `session` refreshes it when asked.
                auth: .init(emitLocalSessionAsInitialSession: true)))
    }
}

/// Accounts on the Supabase project: signed in with Apple, with Spotify, or
/// with nothing at all.
struct SupabaseAccountService: AccountService {
    let client: SupabaseClient
    /// Shows Spotify's page and returns where it sent the browser back to.
    /// The app's own web view, so the Spotify session made here is the one the
    /// player and the music connection use next -- no second password.
    var presentSignIn: @Sendable (URL, String) async throws -> URL = WebAuthentication.presentSignIn

    /// Where Supabase sends the page back after Spotify. The project lists it
    /// among its redirect URLs.
    static let callback = URL(string: "todapp://auth/callback")!

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "account")

    func restore() async -> AccountUser? {
        // `session` refreshes an expired token and throws when there is none,
        // or when it can no longer be refreshed. Either way: signed out.
        guard let session = try? await client.auth.session else { return nil }
        Self.log.notice("session restored")
        return Self.user(of: session)
    }

    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        let user = Self.user(of: session)
        Self.log.notice("signed in with Apple")

        // The profile was made at sign-up, named from the e-mail address --
        // for a hidden Apple address, a string of letters. Apple's name
        // replaces it, the one time Apple gives one.
        if let name {
            do {
                try await client.from("profiles")
                    .update(["name": name])
                    .eq("id", value: user.id)
                    .execute()
            } catch {
                // Not worth failing the sign-in over: the name can be set in
                // the profile.
                Self.log.error("profile name not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        return user
    }

    func signInWithSpotify() async throws -> AccountUser {
        let present = presentSignIn
        let session = try await client.auth.signInWithOAuth(
            provider: .spotify, redirectTo: Self.callback, scopes: "user-read-email"
        ) { url in
            try await present(url, Self.callback.scheme ?? "todapp")
        }
        Self.log.notice("signed in with Spotify")
        return Self.user(of: session)
    }

    func signInAnonymously() async throws -> AccountUser {
        let session = try await client.auth.signInAnonymously()
        Self.log.notice("signed in without an account")
        return Self.user(of: session)
    }

    func signOut() async {
        do {
            // This phone only; other devices stay signed in.
            try await client.auth.signOut(scope: .local)
        } catch {
            // The library drops the local session even when the server call
            // fails, so the app is signed out regardless.
            Self.log.error("sign-out: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The profile picture goes first -- storage is only emptied through the
    /// Storage API, and nobody can remove it once the account is gone -- then
    /// `delete_my_account`, which removes the person and, through the
    /// database's cascades, everything theirs. Groups they started stay for
    /// the others.
    func deleteAccount() async throws {
        guard let session = try? await client.auth.session else { throw TodAppError.notAllowed }
        let folder = Self.user(of: session).id
        let avatars = client.storage.from("avatars")
        if let files = try? await avatars.list(path: folder), !files.isEmpty {
            _ = try? await avatars.remove(paths: files.map { "\(folder)/\($0.name)" })
        }
        do {
            try await client.rpc("delete_my_account").execute()
        } catch {
            Self.log.error("account deletion: \(error.localizedDescription, privacy: .public)")
            throw TodAppError.network(underlying: error)
        }
        Self.log.notice("account deleted")
        try? await client.auth.signOut(scope: .local)
    }

    /// Postgres writes a uuid in lower case; so does the app.
    private static func user(of session: Session) -> AccountUser {
        AccountUser(id: session.user.id.uuidString.lowercased(), isAnonymous: session.user.isAnonymous)
    }
}
