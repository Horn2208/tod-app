import Foundation
import UIKit
import WebKit

/// Spotify's sign-in, inside the app's own web view.
///
/// It used to run in `ASWebAuthenticationSession` -- the system browser, whose
/// cookies this app never sees. The player's embed needs a Spotify session in
/// *this* app's cookie store to play whole songs, so that meant signing in
/// twice. The page runs on the same persistent store as the embed now: one
/// sign-in gives search and posting their token and the player its session.
///
/// Spotify's page is what the person types into; nothing here reads or keeps
/// what they enter. Login with Google, Apple or Facebook often refuses to run
/// inside an embedded web view -- email and password work.
///
/// Still the only place that presents the sign-in, so everything else is
/// tested without a sheet appearing.
enum WebAuthentication {
    @MainActor
    static func presentSignIn(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            SignInFlow(continuation: continuation).start(url: url, callbackScheme: callbackScheme)
        }
    }

    /// One sign-in attempt, owning everything that attempt needs.
    ///
    /// Each attempt keeps itself alive until its own ending has run, and ends
    /// exactly once. An earlier version shared one owner between attempts: a
    /// second sign-in overwrote the first one's, and a continuation was
    /// resumed twice, which traps the process. That crash was real.
    @MainActor
    private final class SignInFlow: NSObject, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
        private let once: SingleResume<URL>
        private var callbackScheme = ""
        private weak var sheet: UINavigationController?
        private var selfReference: SignInFlow?

        init(continuation: CheckedContinuation<URL, Error>) {
            once = SingleResume(continuation)
        }

        func start(url: URL, callbackScheme: String) {
            self.callbackScheme = callbackScheme.lowercased()
            guard let presenter = Self.topViewController() else {
                // No foreground window to show the page in.
                once.resume(throwing: TodAppError.authorizationFailed)
                return
            }

            let configuration = WKWebViewConfiguration()
            // The embed's store: the session made here is the one it plays under,
            // and it survives a relaunch.
            configuration.websiteDataStore = .default()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self

            let page = UIViewController()
            page.view = webView
            page.title = "Bei Spotify anmelden"
            page.navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .cancel,
                primaryAction: UIAction { [weak self] _ in
                    self?.end(.failure(TodAppError.authorizationCancelled))
                })

            let sheet = UINavigationController(rootViewController: page)
            sheet.overrideUserInterfaceStyle = .dark
            sheet.presentationController?.delegate = self
            self.sheet = sheet
            selfReference = self

            webView.load(URLRequest(url: url))
            presenter.present(sheet, animated: true)
        }

        /// Spotify ends the flow by sending the page to `todapp://…`, which a web
        /// view cannot open. That navigation is the answer -- taken, not followed.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url,
                  url.scheme?.lowercased() == callbackScheme else { return .allow }
            end(.success(url))
            return .cancel
        }

        /// A page that cannot load at all -- no network -- ends the attempt
        /// instead of leaving a blank sheet. The cancelled hop to `todapp://`
        /// reports itself as a failure too, but in WebKit's domain, not this one.
        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            guard (error as NSError).domain == NSURLErrorDomain else { return }
            end(.failure(TodAppError.network(underlying: error)))
        }

        /// Swiped away is cancelled, like the button.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            end(.failure(TodAppError.authorizationCancelled))
        }

        private func end(_ result: Result<URL, Error>) {
            // Held for the rest of this call; nil means this attempt already ended.
            guard let owner = selfReference else { return }
            selfReference = nil
            sheet?.dismiss(animated: true)
            switch result {
            case .success(let url): once.resume(returning: url)
            case .failure(let error): once.resume(throwing: error)
            }
            withExtendedLifetime(owner) {}
        }

        /// The top of whatever is showing in the foreground scene -- the profile
        /// is itself a sheet, and the sign-in has to go over it.
        private static func topViewController() -> UIViewController? {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows
                .first(where: \.isKeyWindow)
            var top = window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
}
