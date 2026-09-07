import AuthenticationServices
import Foundation
import UIKit

/// The only place that touches AuthenticationServices, so everything else can
/// be tested without a sheet appearing.
enum WebAuthentication {
    @MainActor
    static func presentSignIn(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            SignInFlow(continuation: continuation).start(url: url, callbackScheme: callbackScheme)
        }
    }

    /// One sign-in attempt, owning everything that attempt needs.
    ///
    /// Two things have to be true at once, and an earlier version got only the
    /// first of them right. The session needs a strong reference or ARC frees
    /// it while the user is still typing their password -- `start()` returns as
    /// soon as the sheet is up, and nothing else holds it. But that reference
    /// must belong to *this* attempt: a single shared slot meant a second
    /// sign-in overwrote the first one's owner, the handlers interleaved, and
    /// one continuation was resumed twice, which traps the process outright.
    /// That crash was real, not theoretical. So each attempt keeps itself alive
    /// and lets go when its own handler has run.
    @MainActor
    private final class SignInFlow {
        private let once: SingleResume<URL>
        private var session: ASWebAuthenticationSession?
        private var selfReference: SignInFlow?

        init(continuation: CheckedContinuation<URL, Error>) {
            once = SingleResume(continuation)
        }

        func start(url: URL, callbackScheme: String) {
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { [weak self] callback, error in
                self?.finish(callback: callback, error: error)
            }
            session.presentationContextProvider = PresentationAnchor.shared
            // Keeps the Spotify session out of Safari's cookie jar and makes a
            // second sign-in ask again rather than silently reusing an account.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            selfReference = self

            // `start()` returns false when it could not present at all -- no
            // foreground window, for instance -- and in that case the
            // completion handler above is never invoked. Without this check
            // the continuation would hang for the life of the process, and
            // `selfReference` just set above would keep this object alive
            // forever right along with it. Tear down exactly as
            // `finish(callback:error:)` does below, since that is the only
            // other place this ever happens.
            guard session.start() else {
                self.session = nil
                defer { selfReference = nil }
                once.resume(throwing: TodAppError.authorizationFailed)
                return
            }
        }

        private func finish(callback: URL?, error: Error?) {
            session = nil
            // Released last: everything above still needs this object.
            defer { selfReference = nil }

            if let callback {
                once.resume(returning: callback)
            } else if let error = error as? ASWebAuthenticationSessionError,
                      error.code == .canceledLogin {
                once.resume(throwing: TodAppError.authorizationCancelled)
            } else {
                once.resume(throwing: TodAppError.authorizationFailed)
            }
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
