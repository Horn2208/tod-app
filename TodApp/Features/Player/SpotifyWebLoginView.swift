import SwiftUI
import WebKit

/// Spotify's own login page, in a web view on the shared, persistent store.
///
/// This is where the session lives that makes the player deliver whole songs:
/// the embed runs in a web view on the same store, so a login made here is the
/// login it plays under, and it survives a relaunch. The person types their
/// credentials into Spotify's page themselves; nothing in this app sees or
/// keeps them.
///
/// Separate from the sign-in used for search and posting, which runs in the
/// system browser and shares no cookies with this app's web views. Login with
/// Google or Apple often refuses to run inside an embedded web view; email and
/// password work.
struct SpotifyWebLoginView: View {
    @Environment(\.dismiss) private var dismiss

    /// After logging in, Spotify sends the page on to its web player -- the
    /// origin the embed plays from, so the session lands where it is needed.
    static let loginURL = URL(
        string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F"
    )!

    var body: some View {
        LoginWebView(url: Self.loginURL)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Bei Spotify anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.todBody(15, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
    }
}

private struct LoginWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The same store as the embed player -- the whole point of this page.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
