import AuthenticationServices
import Foundation
import UIKit

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
            // AuthenticationServices always invokes this from the main thread,
            // but the protocol requirement itself is not statically
            // MainActor-isolated -- assert into that context explicitly so the
            // UIKit calls below type-check under Swift 6 strict concurrency.
            MainActor.assumeIsolated {
                if let window = Self.activeKeyWindow() {
                    return window
                }
                // Last resort only, not the normal path: no foreground window
                // scene -- and therefore no key window -- could be found, e.g.
                // because this fired before the app had any scene in the
                // foreground. A detached window still lets the sheet present
                // instead of crashing.
                return ASPresentationAnchor()
            }
        }

        /// The key window of whichever scene is currently in the foreground.
        /// `UIApplication.shared.keyWindow` is deprecated and single-scene
        /// only; this walks the actual multi-scene API instead.
        @MainActor
        private static func activeKeyWindow() -> UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows
                .first(where: \.isKeyWindow)
        }
    }
}
