import AuthenticationServices
import Foundation

/// The only place that touches AuthenticationServices, so everything else can
/// be tested without a sheet appearing.
enum WebAuthentication {
    // `session.start()` returns as soon as the sheet is presented, and once
    // `presentSignIn` moves on, its local `let session` goes out of scope.
    // Nothing else keeps the session alive: the completion handler below does
    // not capture `session` itself, and `presentationContextProvider` only
    // holds a non-owning back-reference to it. Without a strong reference
    // stored somewhere, ARC is free to deallocate the session while the user
    // is still mid sign-in -- Apple's own samples keep the session in a
    // stored property for exactly this reason. Do not "clean this up" into a
    // local; it has to outlive the function call that creates it.
    @MainActor
    private static var activeSession: ASWebAuthenticationSession?

    @MainActor
    static func presentSignIn(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callback, error in
                // The flow is finished either way -- release the session now
                // that its completion handler has run.
                activeSession = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: TodAppError.authorizationCancelled)
                } else {
                    continuation.resume(throwing: TodAppError.authorizationFailed)
                }
            }
            session.presentationContextProvider = PresentationAnchor.shared
            // Keeps the Spotify session out of Safari's cookie jar and makes a
            // second sign-in ask again rather than silently reusing an account.
            session.prefersEphemeralWebBrowserSession = true
            activeSession = session
            session.start()
        }
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = PresentationAnchor()

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            ASPresentationAnchor()
        }
    }
}
