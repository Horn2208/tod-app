import SwiftUI
import WebKit

/// Puts a player's web view into the view hierarchy at no size at all.
///
/// It has to be *in* the hierarchy: a web view with no window is throttled and
/// stops reporting, so an object holding one off to the side plays nothing.
/// Hosted exactly once per player, at the root, so that the player survives
/// every sheet that opens and closes over it.
struct EmbedHostView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
