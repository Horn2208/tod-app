@preconcurrency import SpotifyiOS
import Foundation
import UIKit
import Observation
import os

/// Where Spotify said it was, and when. Between its reports the player counts
/// on by itself -- Spotify reports changes, not every second.
struct RemoteClock: Equatable, Sendable {
    var positionMs: Int
    var at: Date
    var isPaused: Bool
    var durationMs: Int

    /// Seconds into the song at `now`, never past its end.
    func position(at now: Date) -> Double {
        let reported = Double(positionMs) / 1000
        guard !isPaused else { return reported }
        let counted = reported + max(now.timeIntervalSince(at), 0)
        return durationMs > 0 ? min(counted, Double(durationMs) / 1000) : counted
    }
}

/// What to do about the picked section, given what Spotify just reported.
///
/// Seeking the moment App Remote connects was too early: the Spotify app was
/// still starting the song, and the song then began at zero anyway (seen on
/// the phone, 26 September). So the seek waits for Spotify to report that
/// this very song is playing, and counts as done only once a report shows it
/// at the section.
enum RemoteSectionSeek: Equatable {
    /// Not this song yet, or not playing yet.
    case wait
    case seek(toMs: Int)
    /// At the section, or there is none: nothing left to do.
    case done

    /// A report this close before the section counts as there.
    static let toleranceMs = 1_500

    static func decide(targetURI: String, startMs: Int?, reportedURI: String, positionMs: Int, isPaused: Bool) -> Self {
        guard let startMs else { return .done }
        guard reportedURI == targetURI, !isPaused else { return .wait }
        return positionMs >= startMs - toleranceMs ? .done : .seek(toMs: startMs)
    }
}

/// Spotify's App Remote: the whole song in the listener's own Spotify app,
/// from the picked section, and straight back to TodApp -- whose player then
/// shows and steers what Spotify plays.
///
/// `authorizeAndPlayURI` opens the Spotify app, which asks once for the
/// `app-remote-control` permission, starts the song and hands back to TodApp
/// at `redirect` with an access token. With that token App Remote connects to
/// the running Spotify app, moves the song to the section and subscribes to
/// Spotify's player state: which song, where, paused or not. Only the client
/// id is needed -- no secret: the Spotify app issues the token itself. The
/// app's bundle id has to be registered on Spotify's dashboard for this.
///
/// Every step is logged (`category == "remote"`).
@MainActor
@Observable
final class SpotifyRemote: NSObject {
    /// The redirect already registered for this app on Spotify's dashboard.
    static let redirect = URL(string: "todapp://auth/spotify")!

    nonisolated private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "remote")

    @ObservationIgnored private let appRemote: SPTAppRemote
    /// The song to move to the section, and where that is, until Spotify
    /// reports it there (`RemoteSectionSeek`).
    @ObservationIgnored private var pendingSeek: (uri: String, startMs: Int)?
    @ObservationIgnored private var seekAttempts = 0
    @ObservationIgnored private var lastSeekAt: Date?
    /// Seeks per song before giving up, so a Spotify that keeps refusing
    /// is not asked forever.
    private static let maxSeekAttempts = 3
    /// A press made while the connection was down, run once it is back.
    @ObservationIgnored private var pendingAction: (@MainActor () -> Void)?
    @ObservationIgnored private var hasToken = false
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var clock: RemoteClock?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// What went wrong, in German, for the player to show.
    private(set) var failure: String?
    /// The song Spotify has loaded, as `spotify:track:…`. Nil until Spotify
    /// has said.
    private(set) var trackURI: String?
    private(set) var isPaused = true
    /// Seconds, counted on between Spotify's reports.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isConnected = false

    init(clientID: String) {
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: Self.redirect)
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .info)
        super.init()
        appRemote.delegate = self
    }

    nonisolated static func uri(for source: TrackSource) -> String {
        "spotify:track:\(source.serviceTrackID)"
    }

    /// Where the song starts, in milliseconds; nil for the very start.
    nonisolated static func seekPosition(start: Double?) -> Int? {
        guard let start, start >= 1 else { return nil }
        return Int(start * 1000)
    }

    /// Whether the Spotify app is on this phone. `spotify` is listed under
    /// `LSApplicationQueriesSchemes`, so iOS answers.
    var isAppInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
    }

    /// Whether this is the song Spotify has loaded -- playing or paused.
    func isCurrent(_ source: TrackSource) -> Bool {
        trackURI == Self.uri(for: source)
    }

    var progress: Double { duration > 0 ? min(position / duration, 1) : 0 }

    // MARK: - Commands

    /// Plays `source` in the Spotify app from `start`. `onMissingApp` runs
    /// when the Spotify app is not installed.
    func play(_ source: TrackSource, from start: Double?, onMissingApp: @escaping @MainActor @Sendable () -> Void) {
        failure = nil
        let uri = Self.uri(for: source)
        pendingSeek = Self.seekPosition(start: start).map { (uri: uri, startMs: $0) }
        seekAttempts = 0
        lastSeekAt = nil
        if appRemote.isConnected, let player = appRemote.playerAPI {
            Self.log.notice("already connected, playing \(uri, privacy: .public)")
            // The seek follows Spotify's report that the song plays (`apply`).
            player.play(uri) { _, error in
                if let error { Self.log.error("play failed: \(error.localizedDescription, privacy: .public)") }
            }
            return
        }
        Self.log.notice("authorize and play \(uri, privacy: .public)")
        appRemote.authorizeAndPlayURI(uri) { installed in
            Self.log.notice("Spotify app opened: \(installed)")
            if !installed {
                Task { @MainActor in onMissingApp() }
            }
        }
    }

    func togglePause() {
        whenConnected { [weak self] in
            guard let self, let player = appRemote.playerAPI else { return }
            if isPaused { player.resume(nil) } else { player.pause(nil) }
        }
    }

    /// Seconds from the start of the song.
    func seek(to seconds: Double) {
        let position = Int(max(0, seconds) * 1000)
        whenConnected { [weak self] in
            self?.appRemote.playerAPI?.seek(toPosition: position, callback: nil)
        }
    }

    /// The hand-back from the Spotify app. True when the URL was Spotify's.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.redirect.scheme, url.host == Self.redirect.host else { return false }
        let parameters = appRemote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            Self.log.notice("hand-back with a token (\(token.count) characters), connecting")
            appRemote.connectionParameters.accessToken = token
            hasToken = true
            reconnectAttempts = 0
            appRemote.connect()
        } else {
            let reason = parameters?[SPTAppRemoteErrorDescriptionKey] ?? "no token, no error"
            Self.log.error("hand-back without a token: \(reason, privacy: .public)")
            failure = "Spotify hat die Verbindung nicht erlaubt."
        }
        return true
    }

    /// Back in front: take up the connection again, so the player shows what
    /// Spotify did meanwhile.
    func reconnectIfNeeded() {
        guard hasToken, !appRemote.isConnected else { return }
        Self.log.notice("reconnecting on return")
        appRemote.connect()
    }

    /// Spotify asks apps to let go when they leave the screen.
    func disconnect() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    // MARK: - Private

    private func whenConnected(_ action: @escaping @MainActor () -> Void) {
        if appRemote.isConnected {
            action()
        } else if hasToken {
            pendingAction = action
            appRemote.connect()
        }
    }

    /// Moves the song to the section once Spotify reports it playing.
    private func seekIfDue(uri: String, positionMs: Int, paused: Bool) {
        guard let pending = pendingSeek else { return }
        switch RemoteSectionSeek.decide(
            targetURI: pending.uri, startMs: pending.startMs,
            reportedURI: uri, positionMs: positionMs, isPaused: paused
        ) {
        case .wait:
            break
        case .done:
            Self.log.notice("at the section (\(positionMs) ms)")
            pendingSeek = nil
        case .seek(let target):
            // One seek at a time: Spotify's report of the last one may still
            // be on its way.
            if let lastSeekAt, Date().timeIntervalSince(lastSeekAt) < 1 { return }
            guard seekAttempts < Self.maxSeekAttempts else {
                Self.log.error("gave up seeking to \(target) ms after \(self.seekAttempts) attempts")
                pendingSeek = nil
                return
            }
            seekAttempts += 1
            lastSeekAt = Date()
            Self.log.notice("seeking to \(target) ms, attempt \(self.seekAttempts)")
            appRemote.playerAPI?.seek(toPosition: target) { _, error in
                if let error {
                    Self.log.error("seek to \(target) ms failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Spotify reports changes only. A seek it ignored changes nothing,
            // so look again a moment later, from the counted position.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.pendingSeek != nil, let clock = self.clock, let uri = self.trackURI else { return }
                self.seekIfDue(uri: uri, positionMs: Int(clock.position(at: Date()) * 1000), paused: clock.isPaused)
            }
        }
    }

    private func didConnect() {
        isConnected = true
        reconnectAttempts = 0
        Self.log.notice("connected")
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] result, error in
            if let error {
                Self.log.error("player state subscription failed: \(error.localizedDescription, privacy: .public)")
            }
            // The state as it is now. Later ones come as changes
            // (`playerStateDidChange`); a song already playing at the section
            // would otherwise wait for the next change to be seen.
            guard let state = result as? SPTAppRemotePlayerState else { return }
            let uri = state.track.uri
            let positionMs = state.playbackPosition
            let durationMs = Int(state.track.duration)
            let paused = state.isPaused
            MainActor.assumeIsolated {
                self?.apply(uri: uri, positionMs: positionMs, durationMs: durationMs, paused: paused)
            }
        })
        // No seek here: the song may not be playing yet. Spotify's first
        // report after the subscription brings it (`apply`).
        if let pendingAction {
            self.pendingAction = nil
            pendingAction()
        }
    }

    private func didDisconnect(_ error: Error?) {
        isConnected = false
        Self.log.notice("disconnected: \(error?.localizedDescription ?? "cleanly", privacy: .public)")
        // Spotify drops the connection now and then while it plays on
        // ("End of stream"). Taken up again a few times, a moment later.
        guard error != nil, hasToken, reconnectAttempts < 3 else { return }
        reconnectAttempts += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.appRemote.isConnected else { return }
            Self.log.notice("reconnecting, attempt \(self.reconnectAttempts)")
            self.appRemote.connect()
        }
    }

    private func apply(uri: String, positionMs: Int, durationMs: Int, paused: Bool) {
        seekIfDue(uri: uri, positionMs: positionMs, paused: paused)
        let clock = RemoteClock(positionMs: positionMs, at: Date(), isPaused: paused, durationMs: durationMs)
        self.clock = clock
        trackURI = uri
        isPaused = paused
        duration = Double(durationMs) / 1000
        position = clock.position(at: Date())
        ticker?.cancel()
        guard !paused else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let clock = self.clock else { return }
                self.position = clock.position(at: Date())
            }
        }
    }
}

extension SpotifyRemote: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated { didConnect() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        MainActor.assumeIsolated {
            isConnected = false
            Self.log.error("connection failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            if trackURI == nil { failure = "Keine Verbindung zu Spotify." }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        MainActor.assumeIsolated { didDisconnect(error) }
    }
}

extension SpotifyRemote: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let uri = playerState.track.uri
        let positionMs = playerState.playbackPosition
        let durationMs = Int(playerState.track.duration)
        let paused = playerState.isPaused
        MainActor.assumeIsolated {
            Self.log.notice("state: \(uri, privacy: .public) at \(positionMs) ms of \(durationMs), paused \(paused)")
            apply(uri: uri, positionMs: positionMs, durationMs: durationMs, paused: paused)
        }
    }
}
