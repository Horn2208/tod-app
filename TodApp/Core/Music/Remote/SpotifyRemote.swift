@preconcurrency import SpotifyiOS
import Foundation
import Observation
import os

/// Spotify's App Remote: the whole song in the listener's own Spotify app,
/// from the picked section, and straight back to TodApp.
///
/// `authorizeAndPlayURI` opens the Spotify app, which asks once for the
/// `app-remote-control` permission, starts the song and hands back to TodApp
/// at `redirect` with an access token. With that token App Remote connects to
/// the running Spotify app and moves the song to the section. Only the client
/// id is needed -- no secret: the Spotify app issues the token itself. The
/// app's bundle id has to be registered on Spotify's dashboard for this.
///
/// Every step is logged (`category == "remote"`): the hand-back, the token,
/// the connection, the seek.
@MainActor
@Observable
final class SpotifyRemote: NSObject {
    /// The redirect already registered for this app on Spotify's dashboard.
    static let redirect = URL(string: "todapp://auth/spotify")!

    nonisolated private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "remote")

    @ObservationIgnored private let appRemote: SPTAppRemote
    /// Where the song should start once App Remote is connected.
    @ObservationIgnored private var pendingStart: Double?
    /// What went wrong, in German, for the player to show.
    private(set) var failure: String?

    init(clientID: String) {
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: Self.redirect)
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        super.init()
        appRemote.delegate = self
    }

    /// Where the song starts, in milliseconds; nil for the very start.
    nonisolated static func seekPosition(start: Double?) -> Int? {
        guard let start, start >= 1 else { return nil }
        return Int(start * 1000)
    }

    /// Plays `source` in the Spotify app from `start`. `onMissingApp` runs
    /// when the Spotify app is not installed.
    func play(_ source: TrackSource, from start: Double?, onMissingApp: @escaping @MainActor @Sendable () -> Void) {
        failure = nil
        pendingStart = start
        let uri = "spotify:track:\(source.serviceTrackID)"
        if appRemote.isConnected, let player = appRemote.playerAPI {
            Self.log.notice("already connected, playing \(uri, privacy: .public)")
            player.play(uri) { [weak self] _, error in
                MainActor.assumeIsolated {
                    if let error { Self.log.error("play failed: \(error.localizedDescription, privacy: .public)") }
                    self?.seekIfPending()
                }
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

    /// The hand-back from the Spotify app. True when the URL was Spotify's.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.redirect.scheme, url.host == Self.redirect.host else { return false }
        let parameters = appRemote.authorizationParameters(from: url)
        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            Self.log.notice("hand-back with a token (\(token.count) characters), connecting")
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else {
            let reason = parameters?[SPTAppRemoteErrorDescriptionKey] ?? "no token, no error"
            Self.log.error("hand-back without a token: \(reason, privacy: .public)")
            failure = "Spotify hat die Verbindung nicht erlaubt."
        }
        return true
    }

    /// Spotify asks apps to let go when they leave the screen.
    func disconnect() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    private func seekIfPending() {
        guard let position = Self.seekPosition(start: pendingStart) else { return }
        pendingStart = nil
        appRemote.playerAPI?.seek(toPosition: position) { _, error in
            if let error {
                Self.log.error("seek to \(position) ms failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.log.notice("seeked to \(position) ms")
            }
        }
    }
}

extension SpotifyRemote: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        MainActor.assumeIsolated {
            Self.log.notice("connected")
            seekIfPending()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        MainActor.assumeIsolated {
            Self.log.error("connection failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            failure = "Keine Verbindung zu Spotify."
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        MainActor.assumeIsolated {
            Self.log.notice("disconnected: \(error?.localizedDescription ?? "cleanly", privacy: .public)")
        }
    }
}
