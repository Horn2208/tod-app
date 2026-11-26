# TodApp — Spotify- und SoundCloud-Integration

**Datum:** 2026-08-29
**Status:** Implementiert und getestet (Task 8–10 abgeschlossen, finale Prüfung durchgeführt)
**Vorgänger:** [[2026-08-28-todapp-swiftui-design|Architektur-Spec]]
**Umsetzung:** [[2026-08-29-music-embeds|Implementierungsplan]] · [[2026-08-29-music-integration-decisions|Entscheidungen]]
**Übersicht:** [[TodApp]]

## Ziel

Ein geposteter Song soll ein echter Song sein: auffindbar, abspielbar, verknüpft
mit Spotify oder SoundCloud. Damit läuft das Kernkonzept der App — täglich einen
Song teilen, bewerten, auflösen — zum ersten Mal end-to-end statt gegen
Beispieldaten.

## Externe Randbedingungen

Diese Punkte wurden am 2026-08-29 geprüft und bestimmen das Design. Sie sind
Eigenschaften fremder Dienste und können sich ändern.

**SoundCloud gewährt keinen API-Zugang mehr auf Zuruf.** Offene Registrierung
existiert nicht; Zugang läuft über ein manuell geprüftes Formular mit Wartezeiten
von Wochen und ungewissem Ausgang. Eine In-App-Suche für SoundCloud ist deshalb
nicht planbar. Ohne Key nutzbar bleiben der öffentliche oEmbed-Endpunkt und der
HTML-Widget-Player.

**Spotify liefert neuen Apps kein `preview_url` mehr.** Seit dem 27.11.2024 ist
das Feld für neue Web-API-Anwendungen entfernt. Die 30-Sekunden-Vorschau kommt
deshalb nicht aus der Such-API, sondern aus dem offiziellen Embed-Player.

**Volles Abspielen ist ohne Premium-Zwang nicht zu haben.** Spotify verlangt
dafür das iOS-SDK, das die installierte Spotify-App und ein Premium-Konto bei
jedem Nutzer voraussetzt. Das ist bewusst ausgeschlossen.

Quellen: [SoundCloud API Issue #47](https://github.com/soundcloud/api/issues/47),
[Issue #219](https://github.com/soundcloud/api/issues/219),
[Spotify: Changes to the Web API](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api).

## Getroffene Entscheidungen

**Wiedergabe:** Vorschau in der App über die offiziellen Embed-Player beider
Dienste. Kein Login, kein Premium, für jedes Gruppenmitglied gleich. SoundCloud
spielt vollständige Tracks, Spotify 30 Sekunden.

**Song-Auswahl:** Hybrid. Spotify wird durchsucht; Links beider Dienste können
eingefügt werden. Die Asymmetrie ist keine Design-Schwäche, sondern folgt direkt
aus der SoundCloud-Randbedingung oben.

**Zugangsdaten:** Die App spricht die Spotify-API zunächst selbst an, mit dem
Client-Credentials-Flow. Das Secret liegt in einer nicht versionierten
`Secrets.xcconfig`. Der Zugriff liegt hinter einem Repository-Protokoll, sodass
der spätere Umzug auf einen Proxy ein Ein-Datei-Tausch ist.

> **Diese App darf in dieser Form nicht verteilt werden.** Aus einer IPA lässt
> sich das Secret extrahieren. Vor TestFlight oder App Store muss der Proxy aus
> „Migration" unten stehen. Der Prototyp läuft nur auf Geräten des Teams.

## Datenmodell

Neu:

```swift
enum MusicService: String, Codable, Hashable {
    case spotify, soundcloud
}

struct TrackSource: Codable, Hashable {
    var service: MusicService
    var serviceTrackID: String   // Spotify-Track-ID bzw. SoundCloud-Permalink
    var pageURL: URL             // kanonischer Link: Embed und "in App öffnen"
    var artworkURL: URL?
}
```

Ein Suchtreffer oder ein aufgelöster Link, bevor daraus eine Einsendung wird:

```swift
struct TrackCandidate: Identifiable, Hashable {
    var id: String { source.service.rawValue + ":" + source.serviceTrackID }
    var title: String
    var artist: String
    var source: TrackSource
}
```

`TrackCandidate` ist der gemeinsame Nenner beider Wege: Die Spotify-Suche liefert
eine Liste davon, der Link-Import genau einen. Der Post-Flow kennt danach nur
noch diesen Typ und muss nicht wissen, woher der Song kam.

`Submission` erhält genau ein neues, optionales Feld:

```swift
var source: TrackSource?
```

Optional, weil die vorhandenen Seed-Daten in `InMemoryRepository` keine echten
Tracks haben. Ein Pflichtfeld würde sie ungültig machen und erzwingen, dass
zwanzig Beispiel-Songs echte IDs bekommen, bevor irgendetwas läuft. So bleibt
die Änderung additiv.

`track` und `artist` bleiben Strings und sind die Anzeige-Wahrheit; `TrackSource`
beschreibt nur, wo der Song liegt. Damit rendert jede Liste auch dann, wenn ein
Dienst nicht antwortet. `coverColorHex` bleibt als Fallback, wenn `artworkURL`
fehlt oder das Bild nicht lädt.

Nicht im Modell: Audio-Dateien, Caching-Felder, Play-Counts, dienstspezifische
Metadaten. Jedes Feld hier kostet beim Backend-Umzug.

## Suche und Link-Import

Ein neues Protokoll im Stil der sechs bestehenden Repositories:

```swift
protocol MusicSearchRepository {
    func searchTracks(matching query: String) async throws -> [TrackCandidate]
}
```

`SpotifySearchRepository` holt ein Client-Credentials-Token, hält es im Speicher
bis kurz vor Ablauf und ruft `/v1/search?type=track` auf. Das Token-Handling
liegt in einem `actor`, damit parallele Suchen nicht mehrfach Tokens ziehen.

`TrackLinkParser` erkennt `open.spotify.com/track/…`, `spotify:track:…` und
`soundcloud.com/user/track` und liefert Dienst plus Kennung. Für SoundCloud holt
`SoundCloudOEmbedClient` Titel, Artist und Thumbnail vom öffentlichen
oEmbed-Endpunkt — ausdrücklich ohne Key.

Für Spotify-Links gilt dasselbe: `SpotifyOEmbedClient` holt Titel und Cover von
`open.spotify.com/oembed`, ebenfalls ohne Anmeldung und ohne Client-Credentials.
Der ursprüngliche Entwurf wollte die Metadaten aus der Such-API ziehen — das
funktioniert für einen *eingefügten Link* aber nicht, weil dort keine Suche
stattfindet. Ohne diesen Client stünde im Bestätigungsdialog die nackte URL, wo
der Songtitel hingehört. Spotifys oEmbed liefert keinen `author_name`, der Artist
bleibt bei diesem Weg also leer; der Titel wird nicht zerlegt, um einen zu raten.

Das Secret wird über `Secrets.xcconfig` als Build-Setting in die `Info.plist`
gereicht und zur Laufzeit gelesen. Eine `Secrets.example.xcconfig` mit leeren
Werten wird eingecheckt; die echte Datei steht in `.gitignore`. Fehlt der Wert,
wirft das Repository einen benannten Fehler statt still leere Treffer zu liefern.

## Player

`TrackEmbedView` ist ein dünner `UIViewRepresentable`-Wrapper um `WKWebView`. Er
baut aus der `TrackSource` die Embed-URL — `open.spotify.com/embed/track/{id}`
bzw. `w.soundcloud.com/player/?url={permalink}` — färbt den SoundCloud-Player
über dessen `color`-Parameter auf `todAccent` und gibt Spotify sein Dark-Theme
mit.

`allowsInlineMediaPlayback` ist `true`, sonst reißt iOS die Wiedergabe ins
Vollbild. Die Anforderung einer Nutzergeste bleibt aktiv: abgespielt wird erst
auf Tippen im Widget.

**Der Player kommt nicht in die Listen.** Ein `WKWebView` pro Zeile wäre ein
eigener Browser-Prozess je Song; bei zwölf Einsendungen ist das spürbar. Reveal
und Voting behalten ihre leichten Karten, nur mit Artwork statt Farbfläche und
einem Play-Symbol. Der echte Player erscheint beim Antippen in einem `.sheet` —
immer genau einer.

Die Embeds sind fremde Webinhalte und setzen Anbieter-Cookies. Für den Prototyp
unkritisch, relevant für die spätere Datenschutzerklärung.

## Post-Flow

„+ Song posten" öffnet ein Sheet mit zwei Reitern, die in dieselbe Bestätigung
münden.

*Suchen*: Textfeld, Suche nach etwa 300 ms Ruhe, Trefferliste mit Artwork, Titel
und Artist.

*Link einfügen*: Feld mit Einfügen-Button. Der Parser läuft beim Ändern; ein
ungültiger Link wird sofort am Feld gemeldet, nicht erst beim Absenden.

Beide Wege enden bei Artwork, Titel, Artist, Dienst-Kennung und „Posten".
Absenden ruft `AppStore.submit(...)`; das Repository schreibt, die Gruppen werden
neu geladen, `TodayView` kippt auf „✓ Gepostet".

**Abweichung von der Architektur-Spec, bewusst getroffen:** Der Suchzustand liegt
nicht im `AppStore`, sondern in einem `@Observable PostSongModel`, das nur im
Sheet lebt und das `MusicSearchRepository` aus dem Store bekommt. Suchtext,
Debounce-Task, Trefferliste und gewählter Kandidat gehören genau einem Bildschirm
und sind nach dem Schließen Müll. Im Store würde jede andere View sie mit
beobachten. Der `AppStore` bleibt die Wahrheit für alles Gruppenbezogene.

## Fehlerbehandlung

Fehler gehören dahin, wo man sie beheben kann. Das bestehende Muster —
Repository wirft, `AppStore` fängt in `lastError` — gilt weiter für das Absenden.
Such- und Link-Fehler landen im `PostSongModel` und werden am Feld gezeigt, nicht
als App-weiter Alert.

Behandelte Fälle:

- **Secret fehlt oder ist ungültig** — eigener Fall, dessen Meldung
  `Secrets.xcconfig` beim Namen nennt. Der wahrscheinlichste Fehler beim ersten
  Start.
- **Spotify antwortet 429** — eigene Meldung, nicht als allgemeiner
  Netzwerkfehler getarnt.
- **Link nicht erkennbar**, oder Track privat bzw. gelöscht (oEmbed 404) —
  inline am Feld.
- **Embed lädt nicht** — Rückfall auf Artwork plus „In Spotify öffnen" statt
  eines weißen Rechtecks.

## Tests

Getestet wird Logik, nicht was Apple rendert. Kein Test geht ins Netz.

- `TrackLinkParser` gegen eine Tabelle echter URL-Formen, inklusive
  `spotify:track:`-URI, Links mit `?si=`-Tracking-Parameter und SoundCloud-Links
  mit `/sets/` (Playlist, kein Track). Reine Funktion, und der Ort, an dem Fehler
  sonst still durchrutschen.
- Mapping einer aufgezeichneten Spotify-Antwort auf `TrackCandidate`.
- Ablaufverhalten des Token-Caches.
- Zustandsübergänge des `PostSongModel` gegen ein `MockMusicSearchRepository`, im
  Stil des vorhandenen `MockGroupRepository`.

`TrackEmbedView` wird nicht unit-getestet — ein Wrapper ohne eigene Logik, im
Simulator verifiziert.

## Migration zum Proxy

Wenn die App verteilt werden soll: eine Serverless-Funktion (Supabase Edge
Function oder Cloudflare Worker) hält das Secret und reicht die Suche durch.
Daneben entsteht ein `ProxyMusicSearchRepository` mit unveränderter Signatur, und
im `AppStore`-Init wird eine Zeile getauscht. Kein anderer Code weiß, woher die
Treffer kommen. Das Secret wird dabei rotiert, da es zuvor auf Entwicklerrechnern
lag.

## Nicht in diesem Umfang

Volles Abspielen über das Spotify-SDK, Apple Music, Song-Suche über SoundCloud,
Offline-Caching von Artwork, Wiedergabe im Hintergrund, geteilte
Wiedergabelisten.
