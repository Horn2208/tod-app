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

    /// Whether play starts the whole song in the Spotify app, rather than
    /// only the "Spotify öffnen" pill: the song's own play button, the one
    /// on a feed card, and moving the section while posting. Only with the
    /// Spotify app on the phone: without it the press would open a web page
    /// instead of playing. And not where Apple Music plays the whole song
    /// itself, in this app, or may still turn out to (`.waiting`).
    static func startsOnPlay(
        offers: Bool,
        isAppInstalled: Bool,
        appleMusicWholeSongs: Bool,
        route: TrackPlayerSheet.Player
    ) -> Bool {
        guard offers, isAppInstalled else { return false }
        return !(appleMusicWholeSongs && (route == .appleMusic || route == .waiting))
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

/// What the player says about a limit of the service, kept to one short line
/// on screen, with the full explanation behind an (i) -- the first time it
/// explains, after that it would be noise.
enum PlayerHint: Equatable {
    /// Apple's preview: a fixed 30 seconds Apple does not place.
    case applePreview(sectionStart: Double)
    /// Spotify's excerpt, measured: the picked start is not in it.
    case spotifyExcerpt(sectionStart: Double)
    /// SoundCloud's widget, which always starts at the beginning.
    case widgetFromStart

    var short: String {
        switch self {
        case .applePreview: "Vorschau · 30 s"
        case .spotifyExcerpt(let start): "Vorschau · 30 s · ohne \(Spoken.time(start))"
        case .widgetFromStart: "Spielt von Anfang an"
        }
    }

    var detail: String {
        switch self {
        case .applePreview(let start):
            "Apple Music spielt hier eine Vorschau, einen festen Ausschnitt von 30 Sekunden. Ob der Abschnitt ab \(Spoken.time(start)) darin liegt, sagt Apple nicht. Mit Apple-Music-Abo spielt der ganze Song ab dem Abschnitt."
        case .spotifyExcerpt(let start):
            "Spotify liefert hier nur die 30-Sekunden-Vorschau, und der Abschnitt ab \(Spoken.time(start)) ist darin nicht enthalten. Den ganzen Song spielt „Spotify öffnen“."
        case .widgetFromStart:
            "Der Abschnitt ist gesetzt, aber SoundClouds Player lässt sich nicht an eine Stelle schicken: Er spielt den Song von Anfang an."
        }
    }
}

/// The five-second steps a finger feels while dragging along the waveform,
/// the same VoiceOver moves by.
enum ScrubTick {
    static let seconds: Double = 5

    /// Which step the finger is in; nil while there is no length yet.
    static func step(fraction: Double, duration: Double) -> Int? {
        guard duration > 0 else { return nil }
        return Int(min(max(fraction, 0), 1) * duration / seconds)
    }
}
