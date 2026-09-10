import Foundation
import Observation
import WebKit

/// Spotify's embed, driven from Swift instead of shown as Spotify's own widget.
///
/// The page below loads Spotify's iFrame API and hands back an `EmbedController`.
/// The controller can be told to play, pause and seek, and reports where it is
/// through `playback_update`. The web view itself is never seen: it is hosted at
/// zero size and everything on screen is SwiftUI in this app's own colours.
///
/// **One instance, app-wide.** Each web view is its own process, and a new one
/// stops whatever the old one was playing -- which is exactly what happens if a
/// sheet builds its own on every open. `TodApp` makes one and hands it down;
/// nothing else may construct one.
///
/// Whether 30 seconds or the whole song comes out is Spotify's decision, not
/// this app's: it follows the login state of the web view's cookie store. With
/// no Spotify session that is the preview, with a Premium session the full
/// track, and the code here is identical either way.
@MainActor
@Observable
final class SpotifyEmbedPlayer {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        /// The API never answered, or the page failed. The player says so
        /// rather than sitting there looking merely unpressed.
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// What the controller was last told to play. Not "what is audible": that
    /// is `isPaused`, and only the controller knows it.
    private(set) var source: TrackSource?
    private(set) var isPaused = true
    /// Seconds. Spotify reports milliseconds; the conversion happens once, here.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// True while this exact track is the one loaded and running.
    func isPlaying(_ candidate: TrackSource) -> Bool {
        source == candidate && !isPaused
    }

    let webView: WKWebView
    private let bridge = Bridge()
    /// A track asked for before the API answered. Applied once it does, so a
    /// tap during the first second is not silently dropped.
    private var pending: TrackSource?

    init() {
        let configuration = WKWebViewConfiguration()
        // Without this iOS yanks playback into the fullscreen player.
        configuration.allowsInlineMediaPlayback = true
        // Deliberately the opposite of `TrackEmbedView`, which keeps the
        // gesture requirement because the user presses Spotify's own widget.
        // Here the button is in SwiftUI: WebKit cannot see that tap, so a
        // gesture requirement inside the page would make `play()` a no-op --
        // the page is never touched at all.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(bridge, name: Bridge.name)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false

        bridge.onMessage = { [weak self] message in
            self?.handle(message)
        }
        status = .loading
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://open.spotify.com"))
    }

    // MARK: - Commands

    /// Points the controller at a track. Playing is a separate step, so opening
    /// a song does not start noise by itself.
    func load(_ source: TrackSource) {
        guard source.service == .spotify else { return }
        guard self.source != source else { return }
        self.source = source
        position = 0
        duration = 0
        isPaused = true
        guard status == .ready else {
            pending = source
            return
        }
        call("todLoad", argument: "\"spotify:track:\(source.serviceTrackID)\"")
    }

    func play() { call("todPlay") }
    func pause() { call("todPause") }

    func togglePlay(_ source: TrackSource) {
        if self.source != source {
            load(source)
            // A freshly loaded track is paused; the tap that chose it is also
            // the tap that means "play it".
            play()
        } else if duration > 0, position >= duration {
            // Play on a finished track means play it again. Seeking back to
            // zero was not enough: a controller sitting at the end of a
            // preview answered neither `seek` nor `play`, so the track is
            // handed to it again from the start.
            position = 0
            call("todLoad", argument: "\"spotify:track:\(source.serviceTrackID)\"")
            play()
        } else {
            call("todToggle")
        }
    }

    /// Seconds from the start.
    func seek(to seconds: Double) {
        call("todSeek", argument: String(max(0, seconds)))
    }

    private func call(_ function: String, argument: String = "") {
        webView.evaluateJavaScript("window.\(function)(\(argument))")
    }

    // MARK: - Events

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready":
            status = .ready
            if let pending {
                self.pending = nil
                call("todLoad", argument: "\"spotify:track:\(pending.serviceTrackID)\"")
            }
        case "playback":
            // Milliseconds on the wire, seconds everywhere in Swift.
            if let ms = message["position"] as? Double { position = ms / 1000 }
            if let ms = message["duration"] as? Double { duration = ms / 1000 }
            if let paused = message["isPaused"] as? Bool { isPaused = paused }
            // A finished preview goes on reporting itself unpaused, sitting at
            // its own duration. Left alone the mini player kept saying "Spielt
            // gerade" over silence -- measured on a 30-second preview, still
            // claiming it a minute after the sound stopped.
            if duration > 0, position >= duration { isPaused = true }
        case "error":
            status = .failed(message["message"] as? String ?? "Der Player hat sich nicht gemeldet.")
        default:
            break
        }
    }

    /// Receives `window.webkit.messageHandlers` calls. A separate object rather
    /// than this class conforming: `WKUserContentController` holds its handler
    /// strongly, and a player that registered itself would keep itself alive
    /// for the life of the configuration.
    private final class Bridge: NSObject, WKScriptMessageHandler {
        static let name = "tod"
        var onMessage: (([String: Any]) -> Void)?

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { onMessage?(body) }
        }
    }

    /// The whole page. Small on purpose: everything it does is hand the
    /// controller through to Swift and report back.
    private static let page = """
    <!DOCTYPE html>
    <html>
    <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
    <body style="margin:0;background:transparent">
    <div id="embed"></div>
    <script>
      var controller = null;
      function post(message) {
        window.webkit.messageHandlers.tod.postMessage(message);
      }
      window.onSpotifyIframeApiReady = function (IFrameAPI) {
        IFrameAPI.createController(
          document.getElementById('embed'),
          { width: '100%', height: '80' },
          function (embedController) {
            controller = embedController;
            embedController.addListener('playback_update', function (event) {
              post({
                type: 'playback',
                position: event.data.position,
                duration: event.data.duration,
                isPaused: event.data.isPaused
              });
            });
            post({ type: 'ready' });
          }
        );
      };
      window.todLoad = function (uri) { if (controller) controller.loadUri(uri); };
      window.todPlay = function () { if (controller) controller.play(); };
      window.todPause = function () { if (controller) controller.pause(); };
      window.todToggle = function () { if (controller) controller.togglePlay(); };
      window.todSeek = function (seconds) { if (controller) controller.seek(seconds); };
      window.addEventListener('error', function (event) {
        post({ type: 'error', message: String(event.message) });
      });
    </script>
    <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
    </body>
    </html>
    """
}
