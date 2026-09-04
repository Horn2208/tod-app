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
    private(set) var errorMessage: String?
    private(set) var isSearching = false

    private let search: MusicSearchRepository
    private let oEmbed: SoundCloudOEmbedClient
    private let spotifyOEmbed: SpotifyOEmbedClient
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(
        search: MusicSearchRepository,
        oEmbed: SoundCloudOEmbedClient = SoundCloudOEmbedClient(),
        spotifyOEmbed: SpotifyOEmbedClient = SpotifyOEmbedClient(),
        debounce: Duration = .milliseconds(300)
    ) {
        self.search = search
        self.oEmbed = oEmbed
        self.spotifyOEmbed = spotifyOEmbed
        self.debounce = debounce
    }

    func select(_ candidate: TrackCandidate) {
        selected = candidate
        errorMessage = nil
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
        selected = nil

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
        let task = Task { [debounce, search] in
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                let candidates = try await search.searchTracks(matching: trimmed)
                guard !Task.isCancelled else { return }
                self.results = candidates
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.results = []
                self.errorMessage = Self.message(for: error)
            }
            self.isSearching = false
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            selected = nil
            errorMessage = nil
            return
        }
        guard let source = TrackLinkParser.parse(trimmed) else {
            selected = nil
            errorMessage = "Das sieht nicht nach einem Spotify- oder SoundCloud-Track-Link aus."
            return
        }

        errorMessage = nil
        switch source.service {
        case .soundcloud:
            do {
                selected = try await oEmbed.candidate(for: source)
            } catch {
                selected = nil
                errorMessage = Self.message(for: error)
            }
        case .spotify:
            do {
                selected = try await spotifyOEmbed.candidate(for: source)
            } catch {
                // Metadata lookup failed. Still let the user post the raw
                // link rather than blocking the paste -- the parser already
                // has everything needed to embed and post -- but explain why
                // the title looks bare.
                selected = TrackCandidate(title: trimmed, artist: "", source: source)
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Not `private`: `PostSongView` reuses this for `AppStore.lastError` so a
    /// failed post is explained in the same tone as a failed search or link
    /// lookup, instead of duplicating the mapping.
    static func message(for error: Error) -> String {
        switch error {
        case TodAppError.missingSpotifyCredentials:
            return "Spotify-Zugangsdaten fehlen. Trage sie in Secrets.xcconfig ein."
        case TodAppError.rateLimited:
            return "Spotify meldet zu viele Anfragen. Kurz warten und erneut versuchen."
        case TodAppError.trackUnavailable:
            return "Dieser Track ist nicht verfügbar — vielleicht privat oder gelöscht."
        case TodAppError.searchUnavailable:
            return "Die Suche ist gerade nicht erreichbar. Versuch es später noch mal."
        default:
            return "Das hat nicht geklappt. Prüf deine Verbindung."
        }
    }
}
