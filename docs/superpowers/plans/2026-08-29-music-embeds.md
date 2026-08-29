# Spotify- und SoundCloud-Integration — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Einen geposteten Song zu einem echten Song machen — über Spotify suchbar, per Link von beiden Diensten importierbar, in der App abspielbar.

**Architecture:** Ein neues `MusicSearchRepository`-Protokoll reiht sich in die sechs bestehenden Repositories ein; `SpotifySearchRepository` spricht die Spotify-API zunächst direkt an, sodass ein späterer Proxy nur eine Zeile im `AppStore`-Init kostet. Der Link-Import läuft ohne Zugangsdaten über einen reinen Parser plus SoundClouds öffentlichen oEmbed-Endpunkt. Abgespielt wird über die offiziellen Embed-Player beider Dienste in einem `WKWebView`, das nur in einem Sheet lebt, nie in Listenzeilen.

**Tech Stack:** SwiftUI, Swift 6, iOS 17, Swift Testing (`import Testing`), `@Observable`, `WKWebView`, XcodeGen 2.46.

**Spec:** `docs/superpowers/specs/2026-08-29-tod-app-music-embeds-design.md`

## Global Constraints

- Swift 6, `SWIFT_VERSION: "6.0"`, Deployment Target iOS 17.0 — keine API neuer als iOS 17.
- Tests laufen mit Swift Testing (`@Suite`, `@Test`, `#expect`), nicht XCTest. Vorbild: `TodAppTests/AppStoreTests.swift`.
- **Kein Test darf ins Netz gehen.** Netzwerkzugriffe werden über injizierte Abhängigkeiten ersetzt.
- Neue Quelldateien werden von XcodeGen über `sources: - path: TodApp` eingesammelt. Nach dem Anlegen neuer Dateien **immer** `xcodegen generate` laufen lassen und `TodApp.xcodeproj` mitcommitten.
- Farben und Schriften ausschließlich über die bestehenden Tokens (`Color.todAccent`, `.todBody(_:)` usw.), nie roh.
- Jede `ScrollView`-Inhaltsspalte bekommt `.frame(maxWidth: .infinity)` — siehe Commit `ae11114`, das Layout darf nicht wieder von einem zufällig mitrendernden Kind abhängen.
- **Das Spotify-Client-Secret wird nie eingecheckt und nie in eine Antwort geschrieben.** Es lebt allein in `Secrets.xcconfig`, die in `.gitignore` steht.
- Build- und Testbefehl:
  `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`

---

## Dateistruktur

**Neu:**

| Datei | Verantwortung |
|---|---|
| `TodApp/Core/Models/TrackSource.swift` | `MusicService`, `TrackSource`, `TrackCandidate` |
| `TodApp/Core/Music/TrackLinkParser.swift` | URL-Text → `TrackSource` (rein, ohne Netz) |
| `TodApp/Core/Music/EmbedURLBuilder.swift` | `TrackSource` → Embed-URL (rein) |
| `TodApp/Core/Music/SpotifyCredentials.swift` | Liest ID/Secret aus der Info.plist |
| `TodApp/Core/Music/SpotifyTokenProvider.swift` | `actor`, Token holen und cachen |
| `TodApp/Core/Music/SpotifyDTO.swift` | Decodable-Typen der Spotify-Antwort |
| `TodApp/Core/Repositories/MusicSearchRepository.swift` | Protokoll |
| `TodApp/Core/Repositories/SpotifySearchRepository.swift` | Echte Implementierung |
| `TodApp/Core/Music/SoundCloudOEmbedClient.swift` | oEmbed-Auflösung, keyfrei |
| `TodApp/Features/PostSong/PostSongModel.swift` | `@Observable`, Sheet-Zustand |
| `TodApp/Features/PostSong/PostSongView.swift` | Sheet-UI |
| `TodApp/Features/Player/TrackEmbedView.swift` | `WKWebView`-Wrapper |
| `TodApp/Features/Player/TrackPlayerSheet.swift` | Sheet um den Player |
| `Secrets.example.xcconfig` | Vorlage mit leeren Werten |

**Geändert:** `TodApp/Core/Models/Submission.swift`, `TodApp/Core/TodAppError.swift`, `TodApp/Core/AppStore.swift`, `TodApp/Features/Today/TodayView.swift`, `TodApp/Features/Reveal/RevealView.swift`, `project.yml`, `.gitignore`.

---

### Task 1: Datenmodell

**Files:**
- Create: `TodApp/Core/Models/TrackSource.swift`
- Modify: `TodApp/Core/Models/Submission.swift`
- Test: `TodAppTests/TrackSourceTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces: `MusicService`, `TrackSource(service:serviceTrackID:pageURL:artworkURL:)`, `TrackCandidate(title:artist:source:)` mit `var id: String`; `Submission.source: TrackSource?`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/TrackSourceTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct TrackSourceTests {
    @Test
    func candidateIDCombinesServiceAndTrackID() {
        let candidate = TrackCandidate(
            title: "Genesis",
            artist: "Justice",
            source: TrackSource(
                service: .spotify,
                serviceTrackID: "abc123",
                pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
                artworkURL: nil
            )
        )

        #expect(candidate.id == "spotify:abc123")
    }

    @Test
    func submissionWithoutSourceStillDecodes() throws {
        let json = Data("""
        {"id":1,"posterID":"du","track":"Genesis","artist":"Justice",
         "coverColorHex":"#b3527a","comments":[]}
        """.utf8)

        let submission = try JSONDecoder().decode(Submission.self, from: json)

        #expect(submission.source == nil)
        #expect(submission.track == "Genesis")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'TrackCandidate' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Models/TrackSource.swift`:

```swift
import Foundation

enum MusicService: String, Codable, Hashable {
    case spotify, soundcloud
}

/// Where a submitted track actually lives. Display truth stays on
/// `Submission.track` / `.artist`, so lists still render if a service is down.
struct TrackSource: Codable, Hashable {
    var service: MusicService
    var serviceTrackID: String
    var pageURL: URL
    var artworkURL: URL?
}

/// A search hit or a resolved link, before it becomes a Submission.
struct TrackCandidate: Identifiable, Hashable {
    var id: String { "\(source.service.rawValue):\(source.serviceTrackID)" }
    var title: String
    var artist: String
    var source: TrackSource
}
```

In `TodApp/Core/Models/Submission.swift` ein Feld ergänzen (optional, damit die
vorhandenen Seed-Daten gültig bleiben):

```swift
    var comments: [String]
    var source: TrackSource?
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, alle bestehenden Tests weiterhin grün.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Models/TrackSource.swift TodApp/Core/Models/Submission.swift TodAppTests/TrackSourceTests.swift TodApp.xcodeproj
git commit -m "Add TrackSource and TrackCandidate to the submission model"
```

---

### Task 2: Link-Parser

**Files:**
- Create: `TodApp/Core/Music/TrackLinkParser.swift`
- Test: `TodAppTests/TrackLinkParserTests.swift`

**Interfaces:**
- Consumes: `TrackSource`, `MusicService` aus Task 1.
- Produces: `enum TrackLinkParser { static func parse(_ text: String) -> TrackSource? }`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/TrackLinkParserTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct TrackLinkParserTests {
    @Test
    func parsesSpotifyWebLink() throws {
        let source = try #require(
            TrackLinkParser.parse("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
        )
        #expect(source.service == .spotify)
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func stripsSpotifyTrackingParameter() throws {
        let source = try #require(
            TrackLinkParser.parse("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=9f2a")
        )
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func parsesSpotifyURIScheme() throws {
        let source = try #require(TrackLinkParser.parse("spotify:track:4cOdK2wGLETKBW3PvgPWqT"))
        #expect(source.service == .spotify)
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func parsesSoundCloudTrackLink() throws {
        let source = try #require(TrackLinkParser.parse("https://soundcloud.com/artist/some-track"))
        #expect(source.service == .soundcloud)
        #expect(source.serviceTrackID == "https://soundcloud.com/artist/some-track")
    }

    @Test
    func trimsSurroundingWhitespace() throws {
        let source = try #require(
            TrackLinkParser.parse("  https://soundcloud.com/artist/some-track\n")
        )
        #expect(source.service == .soundcloud)
    }

    @Test(arguments: [
        "https://soundcloud.com/artist/sets/some-playlist",  // Playlist, kein Track
        "https://open.spotify.com/album/4cOdK2wGLETKBW3Pvg",  // Album, kein Track
        "https://example.com/track/123",
        "einfach nur text",
        ""
    ])
    func rejectsNonTrackInput(_ input: String) {
        #expect(TrackLinkParser.parse(input) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'TrackLinkParser' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Music/TrackLinkParser.swift`:

```swift
import Foundation

/// Turns pasted text into a TrackSource. Pure and offline: this is where bad
/// input is caught, so every odd URL shape belongs in the test table.
enum TrackLinkParser {
    static func parse(_ text: String) -> TrackSource? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let id = spotifyTrackID(from: trimmed) {
            let page = URL(string: "https://open.spotify.com/track/\(id)")!
            return TrackSource(service: .spotify, serviceTrackID: id, pageURL: page, artworkURL: nil)
        }
        if let page = soundCloudTrackURL(from: trimmed) {
            return TrackSource(
                service: .soundcloud,
                serviceTrackID: page.absoluteString,
                pageURL: page,
                artworkURL: nil
            )
        }
        return nil
    }

    private static func spotifyTrackID(from text: String) -> String? {
        if text.hasPrefix("spotify:track:") {
            let id = String(text.dropFirst("spotify:track:".count))
            return id.isEmpty ? nil : id
        }
        guard let components = URLComponents(string: text),
              components.host == "open.spotify.com" else { return nil }
        // Path is /track/<id>, optionally locale-prefixed: /intl-de/track/<id>
        let parts = components.path.split(separator: "/").map(String.init)
        guard let trackIndex = parts.firstIndex(of: "track"),
              parts.indices.contains(trackIndex + 1) else { return nil }
        return parts[trackIndex + 1]
    }

    private static func soundCloudTrackURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text),
              components.host?.hasSuffix("soundcloud.com") == true else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        // A track is /<user>/<slug>. /sets/ marks a playlist, which we reject.
        guard parts.count == 2, !parts.contains("sets") else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, alle Fälle inklusive der fünf Ablehnungen.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/TrackLinkParser.swift TodAppTests/TrackLinkParserTests.swift TodApp.xcodeproj
git commit -m "Add TrackLinkParser for Spotify and SoundCloud links"
```

---

### Task 3: Embed-URLs

**Files:**
- Create: `TodApp/Core/Music/EmbedURLBuilder.swift`
- Test: `TodAppTests/EmbedURLBuilderTests.swift`

**Interfaces:**
- Consumes: `TrackSource` aus Task 1.
- Produces: `enum EmbedURLBuilder { static func embedURL(for source: TrackSource) -> URL }`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/EmbedURLBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct EmbedURLBuilderTests {
    @Test
    func buildsSpotifyEmbedURL() {
        let source = TrackSource(
            service: .spotify,
            serviceTrackID: "abc123",
            pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
            artworkURL: nil
        )

        let url = EmbedURLBuilder.embedURL(for: source)

        #expect(url.absoluteString == "https://open.spotify.com/embed/track/abc123?theme=0")
    }

    @Test
    func buildsSoundCloudWidgetURLWithBrandColour() throws {
        let page = URL(string: "https://soundcloud.com/artist/some-track")!
        let source = TrackSource(
            service: .soundcloud, serviceTrackID: page.absoluteString,
            pageURL: page, artworkURL: nil
        )

        let url = EmbedURLBuilder.embedURL(for: source)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.host == "w.soundcloud.com")
        #expect(items.contains { $0.name == "url" && $0.value == page.absoluteString })
        #expect(items.contains { $0.name == "color" && $0.value == "#b3527a" })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'EmbedURLBuilder' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Music/EmbedURLBuilder.swift`:

```swift
import Foundation

/// Builds the official embed-player URL for a track. Kept separate from the
/// WKWebView wrapper so the URL shape is testable without a web view.
enum EmbedURLBuilder {
    /// Matches Color.todAccent. Hard-coded because SoundCloud wants a hex string,
    /// not a SwiftUI Color.
    private static let accentHex = "#b3527a"

    static func embedURL(for source: TrackSource) -> URL {
        switch source.service {
        case .spotify:
            // theme=0 is the dark player.
            return URL(string: "https://open.spotify.com/embed/track/\(source.serviceTrackID)?theme=0")!
        case .soundcloud:
            var components = URLComponents(string: "https://w.soundcloud.com/player/")!
            components.queryItems = [
                URLQueryItem(name: "url", value: source.pageURL.absoluteString),
                URLQueryItem(name: "color", value: accentHex),
                URLQueryItem(name: "visual", value: "false"),
                URLQueryItem(name: "hide_related", value: "true")
            ]
            return components.url!
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/EmbedURLBuilder.swift TodAppTests/EmbedURLBuilderTests.swift TodApp.xcodeproj
git commit -m "Add EmbedURLBuilder for both embed players"
```

---

### Task 4: Zugangsdaten und Fehlerfälle

**Files:**
- Create: `TodApp/Core/Music/SpotifyCredentials.swift`, `Secrets.example.xcconfig`
- Modify: `TodApp/Core/TodAppError.swift`, `project.yml`, `.gitignore`
- Test: `TodAppTests/SpotifyCredentialsTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces: `struct SpotifyCredentials { let clientID: String; let clientSecret: String; static func fromBundle(_ bundle: Bundle) throws -> SpotifyCredentials }`; neue Fälle `TodAppError.missingSpotifyCredentials` und `.rateLimited`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/SpotifyCredentialsTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyCredentialsTests {
    /// Bundle cannot be subclassed usefully (no accessible designated init), so
    /// the lookup is injected as a closure instead.
    private func lookup(_ values: [String: String]) -> (String) -> Any? {
        { values[$0] }
    }

    @Test
    func readsCredentialsFromInfoDictionary() throws {
        let credentials = try SpotifyCredentials.from(infoValueForKey: lookup([
            "SpotifyClientID": "id-123", "SpotifyClientSecret": "secret-456"
        ]))

        #expect(credentials.clientID == "id-123")
        #expect(credentials.clientSecret == "secret-456")
    }

    @Test
    func throwsNamedErrorWhenPlaceholderIsStillEmpty() {
        let empty = lookup(["SpotifyClientID": "", "SpotifyClientSecret": ""])

        #expect(throws: TodAppError.missingSpotifyCredentials) {
            try SpotifyCredentials.from(infoValueForKey: empty)
        }
    }

    @Test
    func throwsNamedErrorWhenKeysAreAbsent() {
        #expect(throws: TodAppError.missingSpotifyCredentials) {
            try SpotifyCredentials.from(infoValueForKey: lookup([:]))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'SpotifyCredentials' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/TodAppError.swift` — Fälle ergänzen und `Equatable` machen, damit
`#expect(throws:)` mit konkreten Fällen arbeiten kann:

```swift
import Foundation

enum TodAppError: Error, Equatable {
    case notFound
    case alreadyVoted
    case network(underlying: Error)
    /// Spotify search is unusable until Secrets.xcconfig is filled in.
    case missingSpotifyCredentials
    case rateLimited
    case linkNotRecognised
    case trackUnavailable

    static func == (lhs: TodAppError, rhs: TodAppError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound), (.alreadyVoted, .alreadyVoted),
             (.missingSpotifyCredentials, .missingSpotifyCredentials),
             (.rateLimited, .rateLimited), (.linkNotRecognised, .linkNotRecognised),
             (.trackUnavailable, .trackUnavailable):
            return true
        case let (.network(l), .network(r)):
            return (l as NSError) == (r as NSError)
        default:
            return false
        }
    }
}
```

`TodApp/Core/Music/SpotifyCredentials.swift`:

```swift
import Foundation

struct SpotifyCredentials: Sendable {
    let clientID: String
    let clientSecret: String

    /// Takes the lookup as a closure rather than a Bundle: Bundle has no
    /// accessible designated initialiser, so it cannot be stubbed in a test.
    static func from(infoValueForKey lookup: (String) -> Any?) throws -> SpotifyCredentials {
        let id = lookup("SpotifyClientID") as? String ?? ""
        let secret = lookup("SpotifyClientSecret") as? String ?? ""
        guard !id.isEmpty, !secret.isEmpty else {
            throw TodAppError.missingSpotifyCredentials
        }
        return SpotifyCredentials(clientID: id, clientSecret: secret)
    }

    static func fromBundle(_ bundle: Bundle = .main) throws -> SpotifyCredentials {
        try from(infoValueForKey: { bundle.object(forInfoDictionaryKey: $0) })
    }
}
```

`Secrets.example.xcconfig` (wird eingecheckt, Werte bleiben leer):

```
// Kopiere diese Datei nach Secrets.xcconfig und trage deine Werte ein.
// Secrets.xcconfig ist absichtlich nicht im Repo.
// Werte findest du unter https://developer.spotify.com/dashboard
SPOTIFY_CLIENT_ID =
SPOTIFY_CLIENT_SECRET =
```

An `.gitignore` anhängen:

```
# Spotify-Zugangsdaten -- niemals einchecken
Secrets.xcconfig
```

In `project.yml` beim Target `TodApp` ergänzen:

```yaml
    configFiles:
      Debug: Secrets.xcconfig
      Release: Secrets.xcconfig
```

und unter `settings: base:` desselben Targets:

```yaml
        INFOPLIST_KEY_SpotifyClientID: $(SPOTIFY_CLIENT_ID)
        INFOPLIST_KEY_SpotifyClientSecret: $(SPOTIFY_CLIENT_SECRET)
```

Damit `xcodegen generate` durchläuft, muss die Datei existieren:

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS. Prüfen, dass `git status` **kein** `Secrets.xcconfig` zeigt.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/SpotifyCredentials.swift TodApp/Core/TodAppError.swift TodAppTests/SpotifyCredentialsTests.swift Secrets.example.xcconfig .gitignore project.yml TodApp.xcodeproj
git commit -m "Read Spotify credentials from an untracked xcconfig"
```

---

### Task 5: Token-Cache

**Files:**
- Create: `TodApp/Core/Music/SpotifyTokenProvider.swift`
- Test: `TodAppTests/SpotifyTokenProviderTests.swift`

**Interfaces:**
- Consumes: `SpotifyCredentials`, `TodAppError` aus Task 4.
- Produces: `actor SpotifyTokenProvider` mit `init(credentials:now:fetch:)` und `func token() async throws -> String`. `fetch` hat den Typ `@Sendable (SpotifyCredentials) async throws -> (token: String, expiresIn: TimeInterval)`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/SpotifyTokenProviderTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyTokenProviderTests {
    private let credentials = SpotifyCredentials(clientID: "id", clientSecret: "secret")

    @Test
    func reusesTokenWhileItIsStillValid() async throws {
        let counter = CallCounter()
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { Date(timeIntervalSince1970: 0) },
            fetch: { _ in await counter.increment(); return ("token-1", 3600) }
        )

        let first = try await provider.token()
        let second = try await provider.token()

        #expect(first == "token-1")
        #expect(second == "token-1")
        #expect(await counter.count == 1)
    }

    @Test
    func fetchesAgainOnceTheTokenHasExpired() async throws {
        let counter = CallCounter()
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { clock.current },
            fetch: { _ in
                let n = await counter.increment()
                return ("token-\(n)", 3600)
            }
        )

        _ = try await provider.token()
        clock.current = Date(timeIntervalSince1970: 3600)  // exactly at expiry
        let second = try await provider.token()

        #expect(second == "token-2")
        #expect(await counter.count == 2)
    }
}

actor CallCounter {
    private(set) var count = 0
    @discardableResult func increment() -> Int { count += 1; return count }
}

final class MutableClock: @unchecked Sendable {
    var current: Date
    init(now: Date) { current = now }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'SpotifyTokenProvider' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Music/SpotifyTokenProvider.swift`:

```swift
import Foundation

/// Holds the client-credentials token. An actor so that parallel searches
/// share one token instead of each fetching their own.
actor SpotifyTokenProvider {
    typealias Fetch = @Sendable (SpotifyCredentials) async throws -> (token: String, expiresIn: TimeInterval)

    private let credentials: SpotifyCredentials
    private let now: @Sendable () -> Date
    private let fetch: Fetch

    private var cached: (token: String, expiresAt: Date)?

    /// Renew slightly early so a request never travels with a token that
    /// expires in flight.
    private let safetyMargin: TimeInterval = 30

    init(
        credentials: SpotifyCredentials,
        now: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping Fetch = SpotifyTokenProvider.liveFetch
    ) {
        self.credentials = credentials
        self.now = now
        self.fetch = fetch
    }

    func token() async throws -> String {
        if let cached, cached.expiresAt > now() {
            return cached.token
        }
        let result = try await fetch(credentials)
        let expiresAt = now().addingTimeInterval(max(0, result.expiresIn - safetyMargin))
        cached = (result.token, expiresAt)
        return result.token
    }

    static let liveFetch: Fetch = { credentials in
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let pair = "\(credentials.clientID):\(credentials.clientSecret)"
        let encoded = Data(pair.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.trackUnavailable }
        guard http.statusCode != 429 else { throw TodAppError.rateLimited }
        guard http.statusCode == 200 else { throw TodAppError.missingSpotifyCredentials }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: TimeInterval
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return (decoded.access_token, decoded.expires_in)
    }
}
```

Hinweis für den Test: Mit `safetyMargin` von 30 s läuft ein Token mit
`expiresIn: 3600` bei Startzeit 0 um 3570 ab; der Sprung auf 3600 im zweiten
Test liegt also sicher dahinter.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, beide Tests.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/SpotifyTokenProvider.swift TodAppTests/SpotifyTokenProviderTests.swift TodApp.xcodeproj
git commit -m "Cache the Spotify client-credentials token in an actor"
```

---

### Task 6: Spotify-Suche

**Files:**
- Create: `TodApp/Core/Music/SpotifyDTO.swift`, `TodApp/Core/Repositories/MusicSearchRepository.swift`, `TodApp/Core/Repositories/SpotifySearchRepository.swift`
- Test: `TodAppTests/SpotifySearchRepositoryTests.swift`

**Interfaces:**
- Consumes: `TrackCandidate` (Task 1), `SpotifyTokenProvider` (Task 5).
- Produces: `protocol MusicSearchRepository { func searchTracks(matching query: String) async throws -> [TrackCandidate] }`; `SpotifySearchRepository`; `enum SpotifyResponseMapper { static func candidates(from data: Data) throws -> [TrackCandidate] }`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/SpotifySearchRepositoryTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyResponseMapperTests {
    /// Trimmed copy of a real /v1/search?type=track response.
    private let recorded = Data("""
    {"tracks":{"items":[
      {"id":"4cOdK2wGLETKBW3PvgPWqT","name":"As It Was",
       "artists":[{"name":"Harry Styles"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"},
       "album":{"images":[
         {"url":"https://i.scdn.co/image/large","width":640},
         {"url":"https://i.scdn.co/image/small","width":64}]}},
      {"id":"7ouMYWpwJ422jRcDASZB7P","name":"One More Time",
       "artists":[{"name":"Daft Punk"},{"name":"Romanthony"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/7ouMYWpwJ422jRcDASZB7P"},
       "album":{"images":[]}}
    ]}}
    """.utf8)

    @Test
    func mapsTracksToCandidates() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)

        #expect(candidates.count == 2)
        #expect(candidates[0].title == "As It Was")
        #expect(candidates[0].artist == "Harry Styles")
        #expect(candidates[0].source.service == .spotify)
        #expect(candidates[0].source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func joinsMultipleArtists() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)
        #expect(candidates[1].artist == "Daft Punk, Romanthony")
    }

    @Test
    func picksTheSmallestArtworkAndToleratesNone() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)
        #expect(candidates[0].source.artworkURL?.absoluteString == "https://i.scdn.co/image/small")
        #expect(candidates[1].source.artworkURL == nil)
    }
}

@Suite
struct MusicSearchRepositoryContractTests {
    @Test
    func blankQueryReturnsNoResultsWithoutHittingTheNetwork() async throws {
        let repo = SpotifySearchRepository(
            tokenProvider: SpotifyTokenProvider(
                credentials: SpotifyCredentials(clientID: "id", clientSecret: "s"),
                fetch: { _ in Issue.record("must not fetch a token"); return ("x", 1) }
            ),
            performRequest: { _ in
                Issue.record("must not hit the network for a blank query")
                return (Data(), HTTPURLResponse())
            }
        )

        let results = try await repo.searchTracks(matching: "   ")

        #expect(results.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'SpotifyResponseMapper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Music/SpotifyDTO.swift`:

```swift
import Foundation

/// Mirrors just the slice of Spotify's search response we need. Note there is
/// deliberately no preview_url: Spotify stopped sending it to new apps in
/// November 2024, so previews come from the embed player instead.
enum SpotifyDTO {
    struct SearchResponse: Decodable {
        let tracks: TrackPage
    }
    struct TrackPage: Decodable {
        let items: [Track]
    }
    struct Track: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
        let external_urls: ExternalURLs
        let album: Album
    }
    struct Artist: Decodable { let name: String }
    struct ExternalURLs: Decodable { let spotify: String }
    struct Album: Decodable { let images: [Image] }
    struct Image: Decodable { let url: String; let width: Int? }
}

enum SpotifyResponseMapper {
    static func candidates(from data: Data) throws -> [TrackCandidate] {
        let response = try JSONDecoder().decode(SpotifyDTO.SearchResponse.self, from: data)
        return response.tracks.items.compactMap { track in
            guard let page = URL(string: track.external_urls.spotify) else { return nil }
            // Smallest image: these are thumbnails in a list, not hero art.
            let artwork = track.album.images
                .min { ($0.width ?? .max) < ($1.width ?? .max) }
                .flatMap { URL(string: $0.url) }
            return TrackCandidate(
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                source: TrackSource(
                    service: .spotify,
                    serviceTrackID: track.id,
                    pageURL: page,
                    artworkURL: artwork
                )
            )
        }
    }
}
```

`TodApp/Core/Repositories/MusicSearchRepository.swift`:

```swift
import Foundation

/// The seam. Today this is backed by Spotify directly; once a proxy holds the
/// client secret, a ProxyMusicSearchRepository conforms to the same protocol
/// and only the AppStore init changes.
protocol MusicSearchRepository: Sendable {
    func searchTracks(matching query: String) async throws -> [TrackCandidate]
}
```

`TodApp/Core/Repositories/SpotifySearchRepository.swift`:

```swift
import Foundation

struct SpotifySearchRepository: MusicSearchRepository {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let tokenProvider: SpotifyTokenProvider
    private let performRequest: PerformRequest

    init(
        tokenProvider: SpotifyTokenProvider,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }
    ) {
        self.tokenProvider = tokenProvider
        self.performRequest = performRequest
    }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "20")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await tokenProvider.token())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.trackUnavailable }
        guard http.statusCode != 429 else { throw TodAppError.rateLimited }
        guard http.statusCode == 200 else { throw TodAppError.trackUnavailable }

        return try SpotifyResponseMapper.candidates(from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, vier Tests.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/SpotifyDTO.swift TodApp/Core/Repositories/MusicSearchRepository.swift TodApp/Core/Repositories/SpotifySearchRepository.swift TodAppTests/SpotifySearchRepositoryTests.swift TodApp.xcodeproj
git commit -m "Add Spotify track search behind MusicSearchRepository"
```

---

### Task 7: SoundCloud-Auflösung per oEmbed

**Files:**
- Create: `TodApp/Core/Music/SoundCloudOEmbedClient.swift`
- Test: `TodAppTests/SoundCloudOEmbedClientTests.swift`

**Interfaces:**
- Consumes: `TrackSource`, `TrackCandidate` (Task 1).
- Produces: `struct SoundCloudOEmbedClient` mit `init(performRequest:)` und `func candidate(for source: TrackSource) async throws -> TrackCandidate`; `enum SoundCloudOEmbedMapper { static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate }`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/SoundCloudOEmbedClientTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct SoundCloudOEmbedTests {
    private let source = TrackSource(
        service: .soundcloud,
        serviceTrackID: "https://soundcloud.com/artist/some-track",
        pageURL: URL(string: "https://soundcloud.com/artist/some-track")!,
        artworkURL: nil
    )

    @Test
    func mapsTitleAndAuthor() throws {
        let data = Data("""
        {"title":"Some Track by Artist","author_name":"Artist",
         "thumbnail_url":"https://i1.sndcdn.com/artwork.jpg"}
        """.utf8)

        let candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.title == "Some Track by Artist")
        #expect(candidate.artist == "Artist")
        #expect(candidate.source.artworkURL?.absoluteString == "https://i1.sndcdn.com/artwork.jpg")
        #expect(candidate.source.service == .soundcloud)
    }

    @Test
    func toleratesMissingThumbnail() throws {
        let data = Data("""
        {"title":"Some Track","author_name":"Artist"}
        """.utf8)

        let candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.source.artworkURL == nil)
    }

    @Test
    func reportsUnavailableTrackFor404() async {
        let client = SoundCloudOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://soundcloud.com/oembed")!,
                statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })

        await #expect(throws: TodAppError.trackUnavailable) {
            try await client.candidate(for: source)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'SoundCloudOEmbedMapper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Music/SoundCloudOEmbedClient.swift`:

```swift
import Foundation

/// SoundCloud's oEmbed endpoint is public and needs no API key -- which matters,
/// because SoundCloud no longer grants API credentials on request.
enum SoundCloudOEmbedMapper {
    struct Response: Decodable {
        let title: String
        let author_name: String
        let thumbnail_url: String?
    }

    static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var resolved = source
        resolved.artworkURL = decoded.thumbnail_url.flatMap { URL(string: $0) }
        return TrackCandidate(title: decoded.title, artist: decoded.author_name, source: resolved)
    }
}

struct SoundCloudOEmbedClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func candidate(for source: TrackSource) async throws -> TrackCandidate {
        var components = URLComponents(string: "https://soundcloud.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: source.pageURL.absoluteString)
        ]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TodAppError.trackUnavailable
        }
        return try SoundCloudOEmbedMapper.candidate(from: data, source: source)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, drei Tests.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Music/SoundCloudOEmbedClient.swift TodAppTests/SoundCloudOEmbedClientTests.swift TodApp.xcodeproj
git commit -m "Resolve SoundCloud links through the public oEmbed endpoint"
```

---

### Task 8: Sheet-Zustand

**Files:**
- Create: `TodApp/Features/PostSong/PostSongModel.swift`
- Test: `TodAppTests/PostSongModelTests.swift`

**Interfaces:**
- Consumes: `MusicSearchRepository` (Task 6), `SoundCloudOEmbedClient` (Task 7), `TrackLinkParser` (Task 2).
- Produces: `@MainActor @Observable final class PostSongModel` mit `init(search:oEmbed:debounce:)`, den Properties `query`, `results`, `linkText`, `selected`, `errorMessage`, `isSearching` und den Methoden `queryChanged(_:) async`, `linkTextChanged(_:) async`, `select(_:)`.

- [ ] **Step 1: Write the failing test**

`TodAppTests/PostSongModelTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

struct MockMusicSearchRepository: MusicSearchRepository {
    var candidates: [TrackCandidate] = []
    var error: TodAppError?
    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        if let error { throw error }
        return candidates
    }
}

@Suite
@MainActor
struct PostSongModelTests {
    private func candidate(_ id: String) -> TrackCandidate {
        TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: id,
                pageURL: URL(string: "https://open.spotify.com/track/\(id)")!, artworkURL: nil
            )
        )
    }

    @Test
    func searchPopulatesResults() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.map(\.id) == ["spotify:a"])
        #expect(model.isSearching == false)
    }

    @Test
    func missingCredentialsProduceAnActionableMessage() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .missingSpotifyCredentials),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage?.contains("Secrets.xcconfig") == true)
    }

    @Test
    func rateLimitIsReportedSeparatelyFromOtherFailures() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .rateLimited), debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.errorMessage?.contains("zu viele") == true)
    }

    @Test
    func clearingTheQueryClearsResultsAndError() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]), debounce: .zero
        )
        await model.queryChanged("justice")

        await model.queryChanged("")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func unrecognisedLinkIsReportedAtTheField() async {
        let model = PostSongModel(search: MockMusicSearchRepository(), debounce: .zero)

        await model.linkTextChanged("einfach nur text")

        #expect(model.selected == nil)
        #expect(model.errorMessage?.isEmpty == false)
    }

    @Test
    func spotifyLinkSelectsCandidateWithoutNetworkCall() async {
        let model = PostSongModel(search: MockMusicSearchRepository(), debounce: .zero)

        await model.linkTextChanged("https://open.spotify.com/track/abc123")

        #expect(model.selected?.source.serviceTrackID == "abc123")
        #expect(model.errorMessage == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `cannot find 'PostSongModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Features/PostSong/PostSongModel.swift`:

```swift
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
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        do {
            if debounce > .zero { try await Task.sleep(for: debounce) }
            results = try await search.searchTracks(matching: trimmed)
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = Self.message(for: error)
        }
        isSearching = false
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, sechs Tests.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Features/PostSong/PostSongModel.swift TodAppTests/PostSongModelTests.swift TodApp.xcodeproj
git commit -m "Add PostSongModel with search, link import and field-level errors"
```

---

### Task 9: Player-Sheet

**Files:**
- Create: `TodApp/Features/Player/TrackEmbedView.swift`, `TodApp/Features/Player/TrackPlayerSheet.swift`
- Modify: `TodApp/Features/Reveal/RevealView.swift`

**Interfaces:**
- Consumes: `EmbedURLBuilder` (Task 3), `TrackSource` (Task 1).
- Produces: `struct TrackEmbedView: UIViewRepresentable` mit `init(source: TrackSource)`; `struct TrackPlayerSheet: View` mit `init(candidateTitle: String, artist: String, source: TrackSource)`.

- [ ] **Step 1: Write the implementation**

Dieser Task hat keinen Unit-Test: `TrackEmbedView` ist ein Wrapper ohne eigene
Logik, und die testbare Logik dahinter — der URL-Bau — ist in Task 3 bereits
abgedeckt. Verifiziert wird im Simulator, Schritt 2.

`TodApp/Features/Player/TrackEmbedView.swift`:

```swift
import SwiftUI
import WebKit

/// Thin wrapper around the official embed players. Never put one of these in a
/// list row -- each is its own web process.
struct TrackEmbedView: UIViewRepresentable {
    let source: TrackSource

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Without this iOS yanks playback into the fullscreen player.
        configuration.allowsInlineMediaPlayback = true
        // Keep the user-gesture requirement: nothing starts playing by itself.
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: EmbedURLBuilder.embedURL(for: source)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let target = EmbedURLBuilder.embedURL(for: source)
        guard webView.url != target else { return }
        webView.load(URLRequest(url: target))
    }
}
```

`TodApp/Features/Player/TrackPlayerSheet.swift`:

```swift
import SwiftUI

struct TrackPlayerSheet: View {
    let candidateTitle: String
    let artist: String
    let source: TrackSource

    @Environment(\.dismiss) private var dismiss

    private var embedHeight: CGFloat {
        // Spotify's compact player is shorter than SoundCloud's widget.
        source.service == .spotify ? 152 : 166
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidateTitle)
                    .font(.todDisplay(20))
                    .foregroundStyle(Color.todText)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todTextDim)
                }
            }

            TrackEmbedView(source: source)
                .frame(height: embedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Link(destination: source.pageURL) {
                Text(source.service == .spotify ? "In Spotify öffnen" : "In SoundCloud öffnen")
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todBackground)
        .presentationDetents([.height(340)])
        .presentationBackground(Color.todBackground)
    }
}
```

In `RevealView` die Zeile antippbar machen. Innerhalb von `ForEach` den
bestehenden `HStack` in einen Button hüllen und den State ergänzen:

```swift
struct RevealView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: Submission?
```

Die Farbfläche wird durch das Artwork ersetzt, mit der Farbe als Fallback —
`AsyncImage` reicht, ein Bild-Cache ist ausdrücklich nicht im Umfang. Den
bestehenden `RoundedRectangle` in der Zeile ersetzen durch:

```swift
                        AsyncImage(url: submission.source?.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color(hex: submission.coverColorHex))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
```

Vor dem `Spacer()` in derselben Zeile kommt das Play-Symbol, das nur erscheint,
wenn es etwas abzuspielen gibt:

```swift
                        if submission.source != nil {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Color.todAccent)
                        }
```

Die Karte bekommt am Ende — nach `.clipShape(...)` — eine Bedingung, die nur
Einsendungen mit Quelle antippbar macht:

```swift
                    .onTapGesture {
                        if submission.source != nil { playing = submission }
                    }
```

und auf der `ScrollView`, neben `.navigationTitle("Reveal")`:

```swift
        .sheet(item: $playing) { submission in
            if let source = submission.source {
                TrackPlayerSheet(
                    candidateTitle: submission.track,
                    artist: submission.artist,
                    source: source
                )
            }
        }
```

- [ ] **Step 2: Verify in the simulator**

```bash
xcodegen generate
xcodebuild -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Dann die App starten, in den Reveal-Tab wechseln und eine Einsendung antippen.
Erwartet: Die Seed-Einsendungen haben **keine** Quelle und reagieren deshalb
nicht — das ist korrekt. Der Player wird in Task 10 mit einem frisch geposteten
Song geprüft. Der Build muss fehlerfrei sein und die Liste unverändert scrollen.

- [ ] **Step 3: Commit**

```bash
git add TodApp/Features/Player TodApp/Features/Reveal/RevealView.swift TodApp.xcodeproj
git commit -m "Add embed player in a sheet, opened from Reveal rows"
```

---

### Task 10: Post-Flow verdrahten

**Files:**
- Create: `TodApp/Features/PostSong/PostSongView.swift`
- Modify: `TodApp/Core/AppStore.swift`, `TodApp/Features/Today/TodayView.swift`

**Interfaces:**
- Consumes: `PostSongModel` (Task 8), `TrackPlayerSheet` (Task 9), `SpotifySearchRepository` (Task 6).
- Produces: `AppStore.musicSearch: MusicSearchRepository`, `AppStore.post(candidate:)`; `PostSongView`.

- [ ] **Step 1: Write the failing test**

An `TodAppTests/AppStoreTests.swift` anhängen. Wichtig: Ohne eigenes
Submission-Mock liefe der Test gegen `InMemoryRepository.shared`, das die
Testgruppe nicht kennt und `notFound` werfen würde.

```swift
/// Records what the store handed over, so the test can assert the source
/// survived the trip instead of just checking that nothing blew up.
actor RecordingSubmissionRepository: SubmissionRepository {
    private(set) var submitted: [Submission] = []
    func submit(_ submission: Submission, to groupID: String) async throws {
        submitted.append(submission)
    }
    func addComment(_ text: String, submissionID: Int, groupID: String) async throws {}
}

@Suite
@MainActor
struct AppStorePostingTests {
    @Test
    func postingACandidateStoresItsSource() async throws {
        let group = Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], board: [], chatMessages: [], activeBattle: nil
        )
        let submissions = RecordingSubmissionRepository()
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group]),
            submissionRepo: submissions
        )
        await store.loadGroups()
        store.selectGroup("test")

        await store.post(candidate: TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: "abc",
                pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
            )
        ))

        let recorded = try #require(await submissions.submitted.first)
        #expect(recorded.track == "Genesis")
        #expect(recorded.artist == "Justice")
        #expect(recorded.source?.serviceTrackID == "abc")
        #expect(recorded.source?.service == .spotify)
        #expect(store.lastError == nil)
    }
}
```

Dafür muss `AppStoreTests.swift` zusätzlich `import Foundation` haben (für `URL`).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: Compile-Fehler, `value of type 'AppStore' has no member 'post'`.

- [ ] **Step 3: Write minimal implementation**

In `AppStore` die Suche als Abhängigkeit ergänzen. Im Init-Parameterblock:

```swift
        musicSearch: MusicSearchRepository = AppStore.defaultMusicSearch(),
```

und im Rumpf `self.musicSearch = musicSearch` sowie die Property
`let musicSearch: MusicSearchRepository`. Dazu die Fabrik, die den
Zugangsdaten-Fehler bis zur Suche trägt statt beim Start zu knallen:

```swift
    /// Missing credentials must surface in the search field, not as a crash at
    /// launch -- so a failure here becomes a repository that always throws.
    static func defaultMusicSearch() -> MusicSearchRepository {
        do {
            let credentials = try SpotifyCredentials.fromBundle()
            return SpotifySearchRepository(
                tokenProvider: SpotifyTokenProvider(credentials: credentials)
            )
        } catch {
            return FailingMusicSearchRepository(error: .missingSpotifyCredentials)
        }
    }
```

In `MusicSearchRepository.swift` ergänzen:

```swift
struct FailingMusicSearchRepository: MusicSearchRepository {
    let error: TodAppError
    func searchTracks(matching query: String) async throws -> [TrackCandidate] { throw error }
}
```

Und die Post-Methode in `AppStore`, die den bestehenden `submit`-Weg nutzt:

```swift
    func post(candidate: TrackCandidate) async {
        guard let group = currentGroup else { return }
        let submission = Submission(
            id: (group.submissions.map(\.id).max() ?? 0) + 1,
            posterID: currentUserID,
            track: candidate.title,
            artist: candidate.artist,
            coverColorHex: "#b3527a",
            comments: [],
            source: candidate.source
        )
        await submit(submission)
    }
```

`TodApp/Features/PostSong/PostSongView.swift`:

```swift
import SwiftUI

struct PostSongView: View {
    enum Mode: String, CaseIterable { case search = "Suchen", link = "Link einfügen" }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: PostSongModel?
    @State private var mode: Mode = .search

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .background(Color.todBackground)
            .navigationTitle("Song posten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Posten") {
                        guard let candidate = model?.selected else { return }
                        Task {
                            await store.post(candidate: candidate)
                            dismiss()
                        }
                    }
                    .disabled(model?.selected == nil)
                }
            }
        }
        .task {
            if model == nil { model = PostSongModel(search: store.musicSearch) }
        }
    }

    @ViewBuilder
    private func content(_ model: PostSongModel) -> some View {
        VStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch mode {
            case .search:
                TextField("Song oder Artist", text: Binding(
                    get: { model.query },
                    set: { text in Task { await model.queryChanged(text) } }
                ))
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.todSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

            case .link:
                TextField("Spotify- oder SoundCloud-Link", text: Binding(
                    get: { model.linkText },
                    set: { text in Task { await model.linkTextChanged(text) } }
                ))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(Color.todSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if model.isSearching { ProgressView().padding(.top, 4) }

            if let selected = model.selected {
                TrackPlayerSheet(
                    candidateTitle: selected.title,
                    artist: selected.artist,
                    source: selected.source
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.results) { candidate in
                            Button { model.select(candidate) } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.todSurface3)
                                        .frame(width: 40, height: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.title)
                                            .font(.todBody(14, weight: .bold))
                                            .foregroundStyle(Color.todText)
                                        Text(candidate.artist)
                                            .font(.todBody(12))
                                            .foregroundStyle(Color.todTextDim)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.todSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            Spacer(minLength: 0)
        }
    }
}
```

In `TodayView` den bislang leeren Button verdrahten. Property ergänzen:

```swift
    @State private var isPosting = false
```

Den Button ändern:

```swift
                        Button("+ Song posten") { isPosting = true }
                            .buttonStyle(TodPrimaryButtonStyle())
```

und auf der `ScrollView`, neben `.navigationTitle("Heute")`:

```swift
        .sheet(isPresented: $isPosting) { PostSongView() }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS, alle Suites grün.

- [ ] **Step 5: Verify the whole loop in the simulator**

Zuvor die echten Werte eintragen — **das macht der Projektinhaber selbst**:

```bash
open Secrets.xcconfig
```

Dann App starten und prüfen:
1. Heute-Tab, „+ Song posten" → Sheet öffnet sich.
2. Reiter „Suchen", „justice" tippen → Treffer erscheinen. Bei leerer
   `Secrets.xcconfig` erscheint stattdessen der Hinweis auf die Datei — auch das
   ist ein bestandener Test.
3. Treffer wählen → Player erscheint, Play spielt die Vorschau.
4. „Posten" → Sheet schließt, Heute-Tab zeigt „✓ Gepostet" über die volle Breite.
5. Reveal-Tab → der neue Song ist da und öffnet beim Antippen den Player.
6. Reiter „Link einfügen" mit einem SoundCloud-Track-Link → Titel und Artwork
   erscheinen, Player spielt den vollen Track.

- [ ] **Step 6: Commit**

```bash
git add TodApp/Features/PostSong TodApp/Core/AppStore.swift TodApp/Core/Repositories/MusicSearchRepository.swift TodApp/Features/Today/TodayView.swift TodAppTests/AppStoreTests.swift TodApp.xcodeproj
git commit -m "Wire the post flow from search and link import to a real submission"
```

---

## Nach dem Plan

`command graphify update .` laufen lassen, damit der Wissensgraph die neuen
Module kennt, und pushen.
