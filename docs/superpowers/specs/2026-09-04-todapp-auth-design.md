---
tags: [todapp, spec, auth]
---

# TodApp — Anmeldung und Anbieter-Protokoll

**Datum:** 2026-09-04
**Status:** Entwurf, nicht abgenommen
**Vorgänger:** [[2026-08-29-tod-app-music-embeds-design|Musik-Integration]]
**Übersicht:** [[TodApp]]

## Warum

Heute spricht die App die Spotify-Suche mit einem Client-Secret an, das in der
App liegt. Aus einer IPA lässt es sich extrahieren, deshalb ist die Verteilung
gesperrt. Der halb gebaute Proxy löst das, verlangt aber einen eigenen Dienst.

Meldet sich stattdessen **jeder Nutzer selbst an**, verschwindet das Secret: der
PKCE-Fluss braucht nur die öffentliche Client-ID. Dieselbe Anmeldung macht
außerdem den Abschnittswähler echt — mit einem Nutzer-Token kann die App sagen,
ab welcher Millisekunde ein Track spielen soll.

## Externe Randbedingungen

Am 2026-09-04 gegen die Dienste selbst geprüft. Es sind fremde Eigenschaften und
können sich ändern.

**Spotify: Authorization Code mit PKCE, kein Secret.** Die App braucht nur die
Client-ID. Der Token gilt für Suche *und* Wiedergabesteuerung.

**Spotify spielt nur für Premium.** `PUT /v1/me/player/play` nimmt `position_ms`
entgegen — genau der gesuchte „fang hier an" — aber Spotifys Doku sagt
wörtlich: *„This API only works for users who have Spotify Premium."* Ein
angemeldetes Gratis-Konto kann suchen und nichts steuern.

**Spotify spielt nicht in dieser App.** Die Wiedergabe läuft über Spotify
Connect auf einem aktiven Gerät des Nutzers. Ohne aktives Gerät antwortet die
API mit `NO_ACTIVE_DEVICE`. Ohne das Spotify-iOS-SDK kann die App kein Gerät
wecken; sie kann nur sagen, dass eines fehlt.

**Apple Music spricht kein OAuth.** Autorisierung läuft über MusicKit
(`MusicAuthorization.request()`) plus einen Developer-Token — ein JWT, signiert
mit einem MusicKit-Schlüssel aus einem **kostenpflichtigen** Apple-Developer-Konto.
Ohne dieses Konto ist nichts davon baubar. Dafür spielt `ApplicationMusicPlayer`
für Abonnenten volle Tracks **innerhalb der App**, mit Sprung an jede Position —
die beste Abschnitts-Erfahrung aller Anbieter.

**SoundCloud vergibt keine Zugangsdaten auf Zuruf.** Der OAuth-Endpunkt lebt
(`invalid_client` auf einen Testaufruf), aber er verlangt eine registrierte App,
und die Registrierung läuft über ein manuell geprüftes Formular mit Wochen
Wartezeit und ungewissem Ausgang.

**Odesli/song.link ist keine freie Quelle mehr.** Der in der Konzeptnotiz
genannte Endpunkt antwortet mit `HTTP 401`.

## Entschieden

**Anmeldung ist Pflicht.** Ohne Konto ist die App nicht benutzbar. Damit
entfallen Client Credentials, das Secret und der Proxy.

**Ein Anbieter-Protokoll statt Verzweigungen nach Dienstnamen.** Die Oberfläche
fragt, was ein Anbieter *kann*, nicht wer er ist. Sonst wächst `if service ==
.spotify` durch die Views, und Apple Music — das kein OAuth spricht und einen
eigenen Player mitbringt — passt später nirgends hinein.

**Spotify zuerst, Apple Music vorgesehen, SoundCloud offen.** Apple Music
braucht das Developer-Konto, SoundCloud den Antrag. Beide sollen sich einfügen,
ohne dass das Protokoll sich ändert.

## Das Protokoll

```swift
/// Was ein Anbieter kann. Teils fest, teils erst nach der Anmeldung bekannt --
/// ob volle Tracks laufen, hängt am Abo des angemeldeten Kontos.
struct MusicProviderCapabilities: Equatable, Sendable {
    var canSearch: Bool
    var canPlayFullTracks: Bool
    var canStartAtPosition: Bool
    /// Ob der Ton aus dieser App kommt oder aus der des Dienstes.
    var playsInsideTheApp: Bool
}

protocol MusicProvider: Sendable {
    var service: MusicService { get }
    var isAuthorized: Bool { get async }
    /// Erst nach `authorize()` verlässlich.
    var capabilities: MusicProviderCapabilities { get async }

    func authorize() async throws
    func signOut() async

    func searchTracks(matching query: String) async throws -> [TrackCandidate]
    /// `section == nil` heißt: von vorn.
    func play(_ source: TrackSource, from section: TrackSection?) async throws
    func stop() async
}
```

`MusicSearchRepository` verschwindet nicht, sondern wird von `MusicProvider`
erfüllt — die Suche bleibt dieselbe Naht, nur die Token-Quelle wechselt.

## SpotifyProvider

**Anmeldung.** `ASWebAuthenticationSession` gegen
`https://accounts.spotify.com/authorize` mit `response_type=code`,
`code_challenge_method=S256`, `state` und einem eigenen Schema als
`redirect_uri` (`todapp://auth/spotify`, in Info.plist und im Spotify-Dashboard
eingetragen). Rücktausch gegen `https://accounts.spotify.com/api/token` mit
`grant_type=authorization_code` und dem `code_verifier`. Kein Secret.

**Scopes.** `user-read-private` (liest `product`, also Premium oder nicht),
`user-read-playback-state`, `user-modify-playback-state`. Die Suche braucht
darüber hinaus keinen Scope.

**Fähigkeiten.** Nach der Anmeldung liest der Provider `GET /v1/me`.
`product == "premium"` setzt `canPlayFullTracks` und `canStartAtPosition`;
sonst bleiben beide falsch. `playsInsideTheApp` ist immer falsch.

**Token.** Der Refresh-Token liegt im Keychain, der Access-Token nur im
Speicher. Läuft er ab, erneuert der Provider ihn mit `grant_type=refresh_token`
und der Client-ID — einmal gleichzeitig, wie `SpotifyTokenProvider` es heute
schon macht.

**Wiedergabe.** `PUT /v1/me/player/play` mit `uris` und `position_ms`. Vorher
`GET /v1/me/player/devices`: ist keines aktiv, wirft der Provider
`.noActivePlaybackDevice`, und die Oberfläche bittet darum, Spotify auf einem
Gerät zu öffnen. Das Ende des Abschnitts wird über einen Timer über
`(ende − start)` gestoppt, gefolgt von `PUT /v1/me/player/pause`. Ein Timer ist
ungenauer als Abfragen des Wiedergabestands, kostet aber keine Anfragen im
Sekundentakt; die Ungenauigkeit liegt unter einer Sekunde und betrifft nur, wann
die Musik aufhört.

## Was ein Gratis-Konto sieht

Anmeldung, Suche und Posten funktionieren. Wiedergabe nicht. Für diese
Mitglieder bleibt der heutige Embed-Player die Wiedergabe, und der Abschnitt
bleibt eine Notiz an der Zeile. Die Oberfläche sagt das offen, statt einen
Knopf anzubieten, der `PREMIUM_REQUIRED` zurückgibt.

Das ist die Kehrseite der Pflicht-Anmeldung: sie beseitigt das Secret, nicht die
Zweiklassigkeit.

## Was wegfällt

`ProxyMusicSearchRepository`, das Verzeichnis `proxy/`, `SpotifyCredentials`,
`SpotifyTokenProvider` in seiner Client-Credentials-Form, `Secrets.xcconfig` und
die beiden `Spotify*`-Schlüssel in der Info.plist. `SpotifyResponseMapper` und
`SpotifyDTO` bleiben — der Suchkörper ist derselbe, nur der Token davor ändert
sich.

## Fehler

- Anmeldung abgebrochen: kein Fehler, zurück zum Anmeldebildschirm.
- Token abgelaufen und Erneuerung scheitert: abmelden und erneut anmelden lassen.
- `PREMIUM_REQUIRED` (403): darf nie erscheinen — die Fähigkeiten verhindern den
  Aufruf. Tritt er doch auf, gilt er als Fähigkeits-Irrtum und schaltet
  `canPlayFullTracks` ab.
- `NO_ACTIVE_DEVICE` (404): eigene Meldung, kein allgemeiner Netzfehler.

## Tests

Wie bisher: Logik, nicht was Apple rendert, und nichts geht ins Netz.

- PKCE: `code_verifier`/`code_challenge` gegen die Vorgaben aus RFC 7636,
  `state` wird geprüft und ein fremdes zurückgewiesen.
- Fähigkeiten aus `GET /v1/me`: `premium` schaltet frei, `free` nicht, ein
  fehlendes Feld gilt als nicht freigeschaltet.
- Token-Erneuerung: abgelaufener Token wird einmal erneuert, gleichzeitige
  Aufrufer teilen sich eine Erneuerung.
- Wiedergabe: `position_ms` entspricht dem Abschnittsstart; ohne aktives Gerät
  wird `.noActivePlaybackDevice` geworfen und nicht gespielt.
- Ein zweiter, erfundener Provider im Test beweist, dass die Views nur über
  Fähigkeiten entscheiden und nicht über `MusicService`.

## Nicht in diesem Umfang

Apple Music (wartet auf das Developer-Konto), SoundCloud-Anmeldung (wartet auf
den Antrag), das Spotify-iOS-SDK zum Wecken eines Geräts, Wiedergabe im
Hintergrund, geteilte Wiedergabelisten.

## Voraussetzungen, die nicht in meiner Hand liegen

1. Im Spotify-Dashboard `todapp://auth/spotify` als Redirect-URI eintragen.
2. Für Apple Music: kostenpflichtiges Apple-Developer-Konto und ein
   MusicKit-Schlüssel. Wird ohnehin für TestFlight und App Store gebraucht.
3. Für SoundCloud: der gestellte Antrag.
