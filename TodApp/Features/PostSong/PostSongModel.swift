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
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(
        search: MusicSearchRepository,
        oEmbed: SoundCloudOEmbedClient = SoundCloudOEmbedClient(),
        debounce: Duration = .milliseconds(300)
    ) {
        self.search = search
        self.oEmbed = oEmbed
        self.debounce = debounce
    }

    func select(_ candidate: TrackCandidate) {
        selected = candidate
        errorMessage = nil
    }

    func queryChanged(_ text: String) async {
        query = text
        searchTask?.cancel()

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
            // The parser already has everything we need to embed and post;
            // title and artist are filled in by the search result if the user
            // picks one, and otherwise stay the raw link text.
            selected = TrackCandidate(title: trimmed, artist: "", source: source)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case TodAppError.missingSpotifyCredentials:
            return "Spotify-Zugangsdaten fehlen. Trage sie in Secrets.xcconfig ein."
        case TodAppError.rateLimited:
            return "Spotify meldet zu viele Anfragen. Kurz warten und erneut versuchen."
        case TodAppError.trackUnavailable:
            return "Dieser Track ist nicht verfügbar — vielleicht privat oder gelöscht."
        default:
            return "Das hat nicht geklappt. Prüf deine Verbindung."
        }
    }
}
