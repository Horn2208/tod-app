import Foundation

/// A cover big enough for the full player. Apple's catalog addresses a cover
/// with its size in the last path component (`100x100bb.jpg`), and the same
/// address with another size hands out that size. Addresses without one --
/// Spotify's, already 640 pixels -- are left as they are.
enum ArtworkSize {
    static func large(_ url: URL?, side: Int) -> URL? {
        guard let url else { return nil }
        let last = url.lastPathComponent
        guard let range = last.range(of: #"^\d+x\d+bb"#, options: .regularExpression) else { return url }
        let renamed = last.replacingCharacters(in: range, with: "\(side)x\(side)bb")
        return url.deletingLastPathComponent().appendingPathComponent(renamed)
    }
}

/// Where the back and forward buttons land.
enum PlaybackSkip {
    static let step: Double = 15

    /// Nil when there is no length to move along -- nothing loaded yet. Forward
    /// stops a second before the end, so the song does not run out under the
    /// finger.
    static func target(position: Double, by seconds: Double, duration: Double) -> Double? {
        guard duration > 0 else { return nil }
        return min(max(position + seconds, 0), max(duration - 1, 0))
    }
}

/// How the waveform is coloured: lit up to the playhead, quiet after it, and
/// no hard edge between -- the two fade into each other over `softness` of
/// the line on either side of the playhead.
enum WaveformFill {
    struct Stop: Equatable {
        let location: Double
        let isPlayed: Bool
    }

    static func stops(progress: Double, softness: Double = 0.04) -> [Stop] {
        if progress <= 0 { return [Stop(location: 0, isPlayed: false), Stop(location: 1, isPlayed: false)] }
        if progress >= 1 { return [Stop(location: 0, isPlayed: true), Stop(location: 1, isPlayed: true)] }
        return [
            Stop(location: 0, isPlayed: true),
            Stop(location: max(progress - softness, 0), isPlayed: true),
            Stop(location: min(progress + softness, 1), isPlayed: false),
            Stop(location: 1, isPlayed: false),
        ]
    }
}

/// Spotify Connect: the listener's own Spotify app plays the whole song,
/// starting at the picked section. Spotify lets an app do that only for a
/// Premium account -- and, until the app has Spotify's extended quota, only
/// for the few testers its development mode admits.
enum SpotifyWholeSong {
    static func offers(service: MusicService?, capabilities: MusicProviderCapabilities) -> Bool {
        service == .spotify && capabilities.canStartAtPosition
    }

    /// Runs `play` until it lands. The Spotify app has just been brought to
    /// the front and needs a moment before Spotify's servers can reach it:
    /// until then they answer "no device" or 502, and waiting helps. Any
    /// other refusal ends it at once.
    static func start(
        attempts: Int = 8,
        wait: @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(1)) },
        play: @Sendable () async throws -> Void
    ) async throws {
        var attempt = 1
        while true {
            do {
                try await play()
                return
            } catch let error as TodAppError where error == .noActivePlaybackDevice || error == .trackUnavailable {
                guard attempt < attempts else { throw error }
                attempt += 1
                await wait()
            }
        }
    }

    /// The song in the Spotify app. Opening it wakes the app -- a paused one
    /// in the background is frozen and plays nothing -- and leaves the
    /// listener on the song even when the start does not come through.
    static func appURL(for source: TrackSource) -> URL? {
        URL(string: "spotify:track:\(source.serviceTrackID)")
    }
}

/// The pills that open a song in the services' own apps: Apple Music when
/// the catalog knows the song, and the service the post came from.
enum PlatformLinks {
    enum Kind: Equatable { case appleMusic, spotify, soundcloud }

    struct Link: Equatable, Identifiable {
        let kind: Kind
        let label: String
        let url: URL
        var id: String { label }
    }

    static func links(service: MusicService?, servicePage: URL?, appleMusicPage: URL?) -> [Link] {
        var links: [Link] = []
        if let appleMusicPage {
            links.append(Link(kind: .appleMusic, label: "Music öffnen", url: appleMusicPage))
        }
        if let service, let servicePage {
            switch service {
            case .spotify: links.append(Link(kind: .spotify, label: "Spotify öffnen", url: servicePage))
            case .soundcloud: links.append(Link(kind: .soundcloud, label: "SoundCloud öffnen", url: servicePage))
            }
        }
        return links
    }
}
