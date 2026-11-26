import Foundation
import Observation
import os
import WebKit

/// What SoundCloud's widget has reported, as the player's state. Apart from
/// the web view so it can be tested: the widget speaks in milliseconds and
/// events, the app in seconds and a paused flag.
struct SoundCloudPlayback: Equatable {
    enum Command: Equatable { case seek(to: Double) }

    var position: Double = 0
    var duration: Double = 0
    var isPaused = true
    var failed = false
    /// Where the song should start, sought once playback is under way: the
    /// widget itself always begins at zero.
    var pendingStart: Double?

    /// Takes one report; answers with what the player should do about it.
    @discardableResult
    mutating func apply(_ message: [String: Any]) -> Command? {
        if let ms = message["duration"] as? Double, ms > 0 { duration = ms / 1000 }
        if let ms = message["position"] as? Double { position = ms / 1000 }
        switch message["type"] as? String {
        case "play":
            isPaused = false
            guard let start = pendingStart else { return nil }
            pendingStart = nil
            guard start >= 1, duration == 0 || start < duration else { return nil }
            return .seek(to: start)
        case "pause":
            isPaused = true
        case "finish":
            isPaused = true
            if duration > 0 { position = duration }
        case "error":
            failed = true
        default:
            break
        }
        return nil
    }
}

/// SoundCloud, played hidden and steered by the app's own controls, as
/// Spotify's embed is (`SpotifyEmbedPlayer`): a zero-sized web view holds
/// SoundCloud's official widget and its JavaScript API (`SC.Widget`); the
/// waveform, play button and time on screen are the app's.
///
/// Unlike the visible widget it can start at the picked section: once
/// playback is under way it seeks there (`SoundCloudPlayback`).
///
/// **One instance, app-wide**, made in `TodApp` -- a second web view would
/// silence the first.
@MainActor
@Observable
final class SoundCloudEmbedPlayer {
    enum Status: Equatable { case idle, loading, ready }

    private(set) var status: Status = .idle
    private(set) var source: TrackSource?
    private(set) var state = SoundCloudPlayback()

    var isPaused: Bool { state.isPaused }
    var position: Double { state.position }
    var duration: Double { state.duration }
    /// The widget refused the track -- the view then shows SoundCloud's own.
    var failed: Bool { state.failed }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    func isPlaying(_ candidate: TrackSource) -> Bool {
        source == candidate && !isPaused
    }

    let webView: WKWebView
    private let bridge = Bridge()
    /// A play asked for before the widget said it was ready.
    private var playWhenReady = false

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "soundcloud")

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // The button is SwiftUI; WebKit never sees that tap.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(bridge, name: Bridge.name)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.isUserInteractionEnabled = false
        bridge.onMessage = { [weak self] message in self?.handle(message) }
    }

    /// Points the player at a track without starting it.
    func load(_ source: TrackSource, startAt start: Double? = nil) {
        guard source.service == .soundcloud, self.source != source else { return }
        self.source = source
        state = SoundCloudPlayback()
        state.pendingStart = start
        playWhenReady = false
        status = .loading
        let widget = EmbedURLBuilder.hiddenSoundCloudURL(for: source).absoluteString
        webView.loadHTMLString(Self.page(widgetURL: widget), baseURL: URL(string: "https://soundcloud.com"))
        Self.log.notice("load \(source.pageURL.absoluteString, privacy: .public)")
    }

    func play() {
        guard status == .ready else { playWhenReady = true; return }
        call("todPlay")
    }

    func pause() {
        playWhenReady = false
        call("todPause")
    }

    func togglePlay(_ source: TrackSource, startAt start: Double? = nil) {
        if self.source != source {
            load(source, startAt: start)
            play()
        } else if isPaused {
            // Finished: from the start again, or from the section.
            if duration > 0, position >= duration - 0.75 {
                state.pendingStart = start
                seek(to: 0)
            }
            play()
        } else {
            pause()
        }
    }

    /// Seconds from the start.
    func seek(to seconds: Double) {
        call("todSeek", argument: String(Int(max(0, seconds) * 1000)))
    }

    private func call(_ function: String, argument: String = "") {
        webView.evaluateJavaScript("window.\(function) && window.\(function)(\(argument))")
    }

    private func handle(_ message: [String: Any]) {
        let type = message["type"] as? String ?? ""
        if type == "ready" {
            status = .ready
            Self.log.notice("ready")
            if playWhenReady {
                playWhenReady = false
                call("todPlay")
            }
        }
        if type == "error" { Self.log.error("widget error") }
        if case .seek(let start)? = state.apply(message) {
            Self.log.notice("seeking to the section at \(start) s")
            seek(to: start)
        }
    }

    private final class Bridge: NSObject, WKScriptMessageHandler {
        static let name = "sc"
        var onMessage: (([String: Any]) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { onMessage?(body) }
        }
    }

    /// The widget in an iframe and SoundCloud's API bound to it. Milliseconds
    /// on the wire; `SoundCloudPlayback` turns them into seconds.
    private static func page(widgetURL: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:transparent">
        <iframe id="sc" width="100%" height="166" scrolling="no" frameborder="no" allow="autoplay"
                src="\(widgetURL)"></iframe>
        <script src="https://w.soundcloud.com/player/api.js"></script>
        <script>
          function post(message) { window.webkit.messageHandlers.sc.postMessage(message); }
          var widget = SC.Widget(document.getElementById('sc'));
          var E = SC.Widget.Events;
          widget.bind(E.READY, function () {
            widget.getDuration(function (ms) { post({ type: 'ready', duration: ms }); });
          });
          widget.bind(E.PLAY, function () { post({ type: 'play' }); });
          widget.bind(E.PAUSE, function () { post({ type: 'pause' }); });
          widget.bind(E.FINISH, function () { post({ type: 'finish' }); });
          widget.bind(E.ERROR, function () { post({ type: 'error' }); });
          widget.bind(E.PLAY_PROGRESS, function (e) {
            widget.getDuration(function (ms) {
              post({ type: 'progress', position: e.currentPosition, duration: ms });
            });
          });
          window.todPlay = function () { widget.play(); };
          window.todPause = function () { widget.pause(); };
          window.todSeek = function (ms) { widget.seekTo(ms); };
        </script>
        </body>
        </html>
        """
    }
}
