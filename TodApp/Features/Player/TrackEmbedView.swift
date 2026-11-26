import SwiftUI
import WebKit

/// Whether a response from the embed host means no player will appear. Pulled
/// out of the delegate so the rule can be tested without WebKit rendering
/// anything -- a deleted or private track answers 404.
enum EmbedResponse {
    static func isFailure(statusCode: Int) -> Bool {
        statusCode >= 400
    }
}

/// Thin wrapper around the official embed players. Never put one of these in a
/// list row -- each is its own web process.
struct TrackEmbedView: UIViewRepresentable {
    let source: TrackSource
    /// Raised when the embed will not appear, so the caller can show something
    /// other than a blank rectangle.
    @Binding var didFail: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(didFail: $didFail)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Without this iOS yanks playback into the fullscreen player.
        configuration.allowsInlineMediaPlayback = true
        // Keep the user-gesture requirement: nothing starts playing by itself.
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: EmbedURLBuilder.embedURL(for: source)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let target = EmbedURLBuilder.embedURL(for: source)
        guard webView.url != target else { return }
        webView.load(URLRequest(url: target))
    }

    /// The flag is cleared when a load starts rather than in `updateUIView`,
    /// which would mean writing SwiftUI state in the middle of a view update.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let didFail: Binding<Bool>

        init(didFail: Binding<Bool>) {
            self.didFail = didFail
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            didFail.wrappedValue = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            didFail.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            didFail.wrappedValue = true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            if let http = navigationResponse.response as? HTTPURLResponse,
               EmbedResponse.isFailure(statusCode: http.statusCode) {
                didFail.wrappedValue = true
            }
            return .allow
        }
    }
}
