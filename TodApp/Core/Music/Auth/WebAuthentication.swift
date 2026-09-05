import AuthenticationServices
import Foundation

/// The only place that touches AuthenticationServices, so everything else can
/// be tested without a sheet appearing.
enum WebAuthentication {
    @MainActor
    static func presentSignIn(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callback, error in
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
