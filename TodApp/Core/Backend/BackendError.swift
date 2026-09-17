import Foundation
import Supabase

/// What a refusal from the Supabase project means to the person who tapped.
///
/// The same Postgres code says different things in different places: row
/// level security turning down a vote means the round's day is over, turning
/// down anything else means the person may not do it. So the caller names
/// what it was doing.
enum BackendError {
    enum Context {
        case read, post, vote, join, write
    }

    /// A `TodAppError` for everything except a cancellation, which stays a
    /// `CancellationError`: a request dropped because the screen moved on is
    /// nobody's failure and must not reach an error banner.
    static func map(_ error: Error, context: Context) -> Error {
        switch error {
        case is CancellationError:
            return error
        case let error as URLError where error.code == .cancelled:
            return CancellationError()
        case let error as TodAppError:
            return error
        case let error as PostgrestError:
            return map(code: error.code, context: context, underlying: error)
        case let error as StorageError:
            switch error.statusCode {
            case "401", "403": return TodAppError.notAllowed
            case "404": return TodAppError.notFound
            default: return TodAppError.network(underlying: error)
            }
        case is AuthError:
            return TodAppError.accountSignInFailed
        default:
            return TodAppError.network(underlying: error)
        }
    }

    private static func map(code: String?, context: Context, underlying: Error) -> TodAppError {
        switch code {
        // Row level security, or a missing grant.
        case "42501":
            return context == .vote ? .roundClosed : .notAllowed
        // A unique key. The one a person can run into is one post a day.
        case "23505":
            return context == .post ? .alreadyPosted : .network(underlying: underlying)
        // `join_group` raises this for an unknown or expired code; a bad
        // value in a filter is the same kind of miss.
        case "P0002", "22P02":
            return context == .join ? .inviteInvalid : .notFound
        case "PGRST116":
            return .notFound
        // The token is missing, malformed or expired.
        case "PGRST301", "PGRST302", "PGRST303":
            return .accountSignInFailed
        default:
            return .network(underlying: underlying)
        }
    }
}
