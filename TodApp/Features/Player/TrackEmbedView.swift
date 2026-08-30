import SwiftUI
import WebKit

/// Thin wrapper around the official embed players. Never put one of these in a
/// list row -- each is its own web process.
struct TrackEmbedView: UIViewRepresentable {
    let source: TrackSource

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
        webView.load(URLRequest(url: EmbedURLBuilder.embedURL(for: source)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let target = EmbedURLBuilder.embedURL(for: source)
        guard webView.url != target else { return }
        webView.load(URLRequest(url: target))
    }
}
