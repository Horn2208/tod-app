import Foundation
import Observation
import os
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

    /// Whether the track has run out.
    ///
    /// Deliberately not `position >= duration`. The last update of a preview
    /// arrives just short of the end -- 29.998 against 30.0 -- so an exact
    /// comparison never fires, and the play button fell through to `togglePlay`
    /// on a controller that had nothing left to toggle. That is why pressing
    /// play on a finished preview did nothing at all.
    private var hasFinished: Bool {
        duration > 0 && position >= duration - 0.75
    }

    /// True while this exact track is the one loaded and running.
    func isPlaying(_ candidate: TrackSource) -> Bool {
        source == candidate && !isPaused
    }

    let webView: WKWebView
    private let bridge = Bridge()
    /// A track asked for before the controller existed. Applied once it does,
    /// so a tap during the first second is not silently dropped.
    private var pending: TrackSource?
    /// Holds a play until the embed has said it is ready for the loaded track.
    /// See `EmbedPlayGate` for why that is a different moment from the
    /// controller existing.
    private var gate = EmbedPlayGate()
    /// A play has been asked for and is waiting on the embed. The player says
    /// "startet" rather than looking as if the tap had not registered.
    var isStarting: Bool { gate.isPlayQueued }
    /// What the embed itself reported going wrong -- a track it cannot load, a
    /// playback it cannot start. Shown under the controls instead of leaving
    /// the player to sit silently at 0:00. Cleared by the next track.
    private(set) var embedError: String?

    /// A trace of the embed's lifecycle, for whoever debugs this next. The one
    /// assumption the play gate rests on -- that Spotify's `ready` arrives
    /// after every load -- cannot be seen on screen: a press more than eight
    /// seconds after loading looks the same whether that signal came or the
    /// fallback fired. Read it with
    /// `log show --predicate 'subsystem == "com.lennetschierhorn.TodApp"'`.
    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "embed")

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
        // A store of its own, thrown away with the app.
        //
        // First added on a theory -- that Spotify restored a finished playback
        // position between runs -- which the measurements did not support. It
        // stays for a plainer reason: a Premium account never reaches this
        // player (it plays through the provider and Spotify Connect), so there
        // is no login here worth keeping, and a throwaway store cannot carry
        // anything from one run into the next.
        configuration.websiteDataStore = .nonPersistent()
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
        embedError = nil
        gate.trackLoaded()
        guard status == .ready else {
            pending = source
            return
        }
        sendLoad(source)
    }

    /// Plays the loaded track -- now, or as soon as the embed is ready for it.
    func play() {
        let generation = gate.generation
        if gate.requestPlay() {
            Self.log.notice("play sent at once, generation \(generation)")
            call("todPlay")
        } else {
            Self.log.notice("play held, generation \(generation)")
        }
    }

    func pause() {
        // Pause while it is still starting means "don't start after all".
        gate.cancelQueuedPlay()
        call("todPause")
    }

    /// Explicit play or pause, never Spotify's `togglePlay`: on a freshly
    /// loaded track that has not played yet, "toggle" is exactly the command
    /// whose meaning depends on state the embed has not settled.
    func togglePlay(_ source: TrackSource) {
        if self.source != source {
            load(source)
            // A freshly loaded track is paused; the tap that chose it is also
            // the tap that means "play it".
            play()
        } else if hasFinished {
            restart()
        } else if isPaused {
            play()
        } else {
            pause()
        }
    }

    /// Builds the page again and starts the current track from the top.
    ///
    /// Why a whole new page rather than a seek to zero is, honestly, unproven.
    /// The earlier attempts -- seek to zero, the same uri again -- sat behind an
    /// end-of-track check that could never fire (see `hasFinished`), so they
    /// were never actually tried. A fresh page is the heavier option; a seek
    /// may well be enough.
    private func restart() {
        guard let source else { return }
        position = 0
        duration = 0
        isPaused = true
        embedError = nil
        pending = source
        // A fresh page means a fresh embed: the play is held until it has
        // loaded the track and said so, like any other first play.
        gate.trackLoaded()
        _ = gate.requestPlay()
        status = .loading
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://open.spotify.com"))
    }

    /// Seconds from the start.
    func seek(to seconds: Double) {
        call("todSeek", argument: String(max(0, seconds)))
    }

    private func call(_ function: String, argument: String = "") {
        webView.evaluateJavaScript("window.\(function)(\(argument))")
    }

    private func sendLoad(_ source: TrackSource) {
        let generation = gate.generation
        Self.log.notice("load sent, generation \(generation)")
        call("todLoad", argument: "\"spotify:track:\(source.serviceTrackID)\"")
        startFallback(for: generation)
    }

    /// If the embed never says it is ready, a held play goes out after a while
    /// anyway -- through Spotify's own queue, which is no worse than before the
    /// gate existed. A play held forever would be a dead button.
    private func startFallback(for generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            let released = self.gate.becameReady(generation: generation)
            Self.log.notice("fallback fired, generation \(generation), released held play: \(released)")
            if released { self.call("todPlay") }
        }
    }

    /// Spotify's own messages are English and technical; its codes are stable.
    private static func describe(embedErrorCode code: String?) -> String {
        switch code {
        case "invalid_uri": "Diesen Song kann Spotify nicht laden."
        case "playback_error": "Spotify konnte den Song nicht abspielen."
        default: "Der Spotify-Player hat einen Fehler gemeldet."
        }
    }

    // MARK: - Events

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready":
            // The controller exists and takes commands. Not yet a sign that
            // anything can play -- that is `trackReady`, once per track.
            status = .ready
            if let pending {
                self.pending = nil
                sendLoad(pending)
            }
        case "trackReady":
            // Spotify's own `ready`: the embed's player has loaded the track.
            // Only now does a held play go out.
            let generation = gate.generation
            let released = gate.becameReady()
            Self.log.notice("embed ready, generation \(generation), released held play: \(released)")
            if released { call("todPlay") }
        case "embedError":
            gate.cancelQueuedPlay()
            let code = message["code"] as? String ?? ""
            Self.log.error("embed error: \(code, privacy: .public)")
            embedError = Self.describe(embedErrorCode: code)
        case "playback":
            // Milliseconds on the wire, seconds everywhere in Swift.
            if let ms = message["position"] as? Double { position = ms / 1000 }
            if let ms = message["duration"] as? Double { duration = ms / 1000 }
            if let paused = message["isPaused"] as? Bool { isPaused = paused }
            // A finished preview goes on reporting itself unpaused, sitting at
            // its own duration. Left alone the mini player kept saying "Spielt
            // gerade" over silence -- measured on a 30-second preview, still
            // claiming it a minute after the sound stopped.
            if hasFinished { isPaused = true }
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
            // Spotify's own ready: fires each time the embed has loaded a
            // track, after it has flushed the commands it was holding.
            embedController.addListener('ready', function () {
              post({ type: 'trackReady' });
            });
            // What the embed reports about the track or its playback --
            // invalid_uri, playback_error. Without this they vanished.
            embedController.addListener('error', function (event) {
              var data = (event && event.data) || {};
              post({ type: 'embedError', code: String(data.code || '') });
            });
            post({ type: 'ready' });
          }
        );
      };
      window.todLoad = function (uri) { if (controller) controller.loadUri(uri); };
      window.todPlay = function () { if (controller) controller.play(); };
      window.todPause = function () { if (controller) controller.pause(); };
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
