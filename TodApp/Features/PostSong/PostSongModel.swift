import Foundation

/// Draft state for the post sheet. Deliberately NOT in AppStore: this state is
/// rubbish the moment the sheet closes, and every other view would observe it.
@MainActor
@Observable
final class PostSongModel {
    var query = ""
    var linkText = ""
    private(set) var results: [TrackCandidate] = []
    private(set) var selected: TrackCandidate?
    /// The stretch of the selected track the poster is pointing at. Lives here
    /// rather than in the picker so it is still around when "Posten" is tapped.
    var section: TrackSection?
    private(set) var errorMessage: String?
    private(set) var isSearching = false

    // Searches through whichever provider is signed in, not the app's own
    // credentials -- the whole point of this task. The model has no idea
    // which service that is, only what it can do.
    private let provider: any MusicProvider
    private let oEmbed: SoundCloudOEmbedClient
    private let spotifyOEmbed: SpotifyOEmbedClient
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    /// Tells a finished search whether it is still the one on screen.
    private var searchGeneration = 0
    /// The same guard for link lookups, which overlap just as easily: a link
    /// typed by hand starts one per keystroke.
    private var linkGeneration = 0

    init(
        provider: any MusicProvider,
        oEmbed: SoundCloudOEmbedClient = SoundCloudOEmbedClient(),
        spotifyOEmbed: SpotifyOEmbedClient = SpotifyOEmbedClient(),
        debounce: Duration = .milliseconds(300)
    ) {
        self.provider = provider
        self.oEmbed = oEmbed
        self.spotifyOEmbed = spotifyOEmbed
        self.debounce = debounce
    }

    func select(_ candidate: TrackCandidate) {
        setSelected(candidate)
        errorMessage = nil
    }

    /// A section belongs to the track it was opened on: carrying one across to
    /// a different pick would point timestamps into a song nobody chose.
    private func setSelected(_ candidate: TrackCandidate?) {
        let changed = candidate?.id != selected?.id
        selected = candidate
        guard changed else { return }
        section = candidate.map { TrackSection.initial(in: assumedTotal(for: $0)) }
    }

    /// SoundCloud's oEmbed carries no length, so the picker works from an
    /// assumption -- and says so on screen rather than passing it off as fact.
    private func assumedTotal(for candidate: TrackCandidate) -> Double {
        guard let seconds = candidate.durationSeconds, seconds > 0 else {
            return TrackSection.assumedDuration
        }
        return Double(seconds)
    }

    func queryChanged(_ text: String) async {
        // SwiftUI's `.task(id:)` re-runs this whenever the Search tab's
        // TextField (re)appears, not only when the bound text truly changes --
        // in particular when the user switches back to this tab from Link
        // and the field remounts with the SAME text it already held. Treating
        // that as real input would clear a selection the Link tab just made,
        // so an unchanged value is a no-op.
        guard text != query else { return }
        query = text
        searchTask?.cancel()
        setSelected(nil)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask = nil
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        // Run the debounce + network call on its own Task so a fast follow-up
        // keystroke can actually cancel it via `searchTask?.cancel()` above.
        // Without this, "cancel the in-flight search" would be a no-op and a
        // slow, superseded response could land after (and clobber) the
        // newest one's results.
        searchGeneration &+= 1
        let generation = searchGeneration
        let task = Task { [debounce, provider] in
            // Cleared on every exit, cancellation included -- the two early
            // returns below used to skip it. Guarded by generation so a
            // superseded search cannot turn off the spinner a newer one lit.
            defer {
                if self.searchGeneration == generation { self.isSearching = false }
            }
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                let candidates = try await provider.searchTracks(matching: trimmed)
                guard !Task.isCancelled else { return }
                self.results = candidates
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.results = []
                self.errorMessage = Self.message(for: error)
            }
        }
        searchTask = task
        await task.value
    }

    func linkTextChanged(_ text: String) async {
        // Same remount problem as `queryChanged`, mirrored: switching to the
        // Link tab (or back to it) remounts its TextField and re-runs this
        // with the SAME text it already held -- most often "" the first time
        // the user ever visits this tab. That must not clobber a selection
        // the Search tab just made; only a genuine change to this field
        // (typing, or actually erasing it) should touch `selected` here.
        guard text != linkText else { return }
        linkText = text
        // Only the newest lookup may land. An older one that fails late would
        // otherwise put "check your connection" under a song that resolved.
        linkGeneration &+= 1
        let generation = linkGeneration
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setSelected(nil)
            errorMessage = nil
            return
        }
        guard let source = TrackLinkParser.parse(trimmed) else {
            setSelected(nil)
            errorMessage = "Das sieht nicht nach einem Spotify- oder SoundCloud-Track-Link aus."
            return
        }

        errorMessage = nil
        switch source.service {
        case .soundcloud:
            do {
                let candidate = try await oEmbed.candidate(for: source)
                guard generation == linkGeneration else { return }
                setSelected(candidate)
            } catch {
                guard generation == linkGeneration else { return }
                setSelected(nil)
                errorMessage = Self.message(for: error)
            }
        case .spotify:
            do {
                let candidate = try await spotifyOEmbed.candidate(for: source)
                guard generation == linkGeneration else { return }
                setSelected(candidate)
            } catch {
                guard generation == linkGeneration else { return }
                // Metadata lookup failed. Still let the user post the raw
                // link rather than blocking the paste -- the parser already
                // has everything needed to embed and post -- but explain why
                // the title looks bare.
                setSelected(TrackCandidate(title: trimmed, artist: "", source: source))
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Not `private`: `PostSongView` reuses this for `AppStore.lastError` so a
    /// failed post is explained in the same tone as a failed search or link
    /// lookup, instead of duplicating the mapping.
    static func message(for error: Error) -> String {
        switch error {
        case TodAppError.rateLimited:
            return "Spotify meldet zu viele Anfragen. Kurz warten und erneut versuchen."
        case TodAppError.trackUnavailable:
            return "Dieser Track ist nicht verfügbar — vielleicht privat oder gelöscht."
        case TodAppError.searchUnavailable:
            return "Die Suche ist gerade nicht erreichbar. Versuch es später noch mal."
        case TodAppError.authorizationFailed:
            // Search still runs through Spotify, so this is also what a search
            // without a Spotify connection answers.
            return "Spotify ist nicht verbunden. Verbinde es im Profil und versuch es noch mal."
        case TodAppError.accountSignInFailed:
            return "Die Anmeldung hat nicht geklappt. Versuch es noch mal."
        case TodAppError.tokenStorageFailed:
            return "Die Anmeldung konnte nicht auf diesem Gerät gespeichert werden."
        case TodAppError.noActivePlaybackDevice:
            return "Spotify spielt gerade nirgends. Öffne Spotify zuerst auf einem Gerät."
        case TodAppError.playbackNotAvailable:
            return "Dieser Account kann nicht zum Abspielen aufgefordert werden. Dafür ist Spotify Premium nötig."
        case TodAppError.alreadyPosted:
            return "Du hast heute in dieser Gruppe schon einen Song gepostet."
        case TodAppError.inviteInvalid:
            return "Diesen Code gibt es nicht, oder er ist abgelaufen."
        case TodAppError.notAllowed:
            return "Das darfst du in dieser Gruppe nicht."
        case TodAppError.roundClosed:
            return "Die Runde ist vorbei. Bewertet wird nur am selben Tag."
        case TodAppError.notFound:
            return "Das gibt es nicht mehr. Zieh die Liste nach unten, um neu zu laden."
        default:
            return "Das hat nicht geklappt. Prüf deine Verbindung."
        }
    }
}
