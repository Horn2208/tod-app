---
tags: [todapp, übergabe]
---

# Übergabe — Stand 10. September 2026, abends

Alles committet und gepusht. Branch `feat/music-embeds`, 90 Commits über `main`,
**277 Tests grün**, keine Build-Warnungen. Offener PR:
[soft233-ttv/tod-app#1](https://github.com/soft233-ttv/tod-app/pull/1).

## Was heute passiert ist

Der Redesign-Prompt (`docs/2026-09-04-redesign-prompt-home-gruppen-profil.md`) ist
bis auf einen Punkt abgearbeitet.

| Commit | Was |
|---|---|
| `bf4ae14` | Anmeldebildschirm: Apple Music und „ohne Musikdienst" als Platzhalter, „Track of the day" unter dem Schriftzug |
| `e3458b5` | Reveal-Regel am Kalendertag verdrahtet, `hasSubmitted`/`submitVotes()` entfernt |
| `9a2157f` | `SongDetailView`: Song, Kommentare, Antwortfeld |
| `a9acb18` | `ProfileView`, „Mehr"-Reiter gelöscht |
| `af86448` | Chat als Gruppen-Hub, Battle hinter Premium |
| `d1f2e9a` | Gruppeneinstellungen, Einlade-Berechtigung, Saisontabelle |
| `f985e51` | Swipe-Feed statt Voten- und Reveal-Liste, Bewertungs-Notizen |
| `c8e793f` | Rangliste auf echte Zahlen, Cover-Schein, Gold-Verlauf |

## Was als Nächstes ansteht

**Spotify über die iFrame API**, der letzte offene Punkt des Prompts. Statt Spotifys
fertigem Embed-Widget soll ein eigener Mini-Player laufen: die WebView wird unsichtbar,
und ein `EmbedController` (`play`, `pause`, `seek`, Events `playback_update` mit
`position`/`duration`/`isPaused`) treibt eine SwiftUI-Oberfläche in den eigenen Farben.

Der Einstieg liegt bei `TrackEmbedView` und `EmbedURLBuilder`. Zwei Dinge, die den
Umbau bestimmen:

- **Eine einzige WebView-Instanz, app-weit.** Jede `TrackEmbedView` ist ein eigener
  Web-Prozess, und eine neue Instanz beim Öffnen oder Schließen eines Sheets stoppt
  die Wiedergabe. Der Zustand gehört in ein app-weites `@Observable`-Objekt, das
  Mini-Player und Vollansicht teilen.
- **Der Login entscheidet nur Vorschau gegen ganzen Song.** Ohne eingeloggten
  Spotify-Account laufen 30 Sekunden, mit Premium-Session der volle Titel — das
  entscheidet Spotify serverseitig. Die Mechanik (Abspielen, Position, Pause) lässt
  sich also ohne Account prüfen, die volle Länge nicht.

SoundCloud bleibt vorerst beim Embed-Widget; für die iFrame API gibt es dort kein
Gegenstück.

## Regeln, die dieses Projekt sich gegeben hat

- **Keine Emoji auf Home** (ausdrücklicher Wunsch). SF Symbols stattdessen; die Streak
  trägt `todStreak`, das Notenzeichen `todAccent`. Gruppen-Emoji als Bild-Rückfall
  bleiben davon unberührt.
- Oberflächentexte **auf Deutsch**, informelles „du", keine Ausrufezeichen. Kommentare im
  Code auf Englisch. Das Bundle deklariert `CFBundleLocalizations: [de]` — ohne das
  kamen Systemtexte (relative Zeitangaben, Dialogknöpfe) auf Englisch zurück.
- Keine View verzweigt nach Dienstnamen — nur nach `MusicProviderCapabilities`.
- Reine Rechenregeln leben ohne SwiftUI und werden dort getestet: `TrackSection`,
  `Streak`, `GroupsFeed`, `RoundVisibility`, `SeasonScore`, `GroupPermissions`,
  `CommentTime`.
- **Der Glanz bleibt sparsam.** Genau zwei Stellen tragen einen Verlauf statt einer
  flachen Farbe: die Streak-Zahl und der Tabellenkopf. Mehr, und er hört auf, etwas
  zu bedeuten.
- Geteilte Test-Helfer gehören in `TodAppTests/TestSupport.swift`.
- Nach jeder neuen Datei `xcodegen generate` **und** die erzeugte `project.pbxproj`
  mitcommitten. Der Fehler lautet sonst „Typ nicht gefunden", obwohl die Datei
  danebenliegt.
- Ein Test, der nicht scheitern kann, wird gelöscht statt aufgepolstert.
- **Kein Knopf ohne Wirkung.** „Battle starten" und „Vote abschicken" sind beide
  verschwunden, weil sie nichts taten bzw. nichts mehr tun sollten. Ein Knopf, der
  einen Tipp schluckt, lehrt Leute, dass die App kaputt ist.

## Fallen, die heute Zeit gekostet haben

- **`Comment` ist zweideutig.** Swift Testing hat einen eigenen `Comment`, und
  `TodApp.Comment` löst nicht auf, weil das App-Struct auch `TodApp` heißt. In Tests
  keine `[Comment]`-Annotation schreiben — über die `Submission` gehen.
- **`Date.RelativeFormatStyle` ignoriert ein übergebenes `now`** und misst immer gegen
  die echte Uhr. `RelativeDateTimeFormatter` nimmt ein Bezugsdatum — nur damit ist die
  Regel testbar. Siehe `CommentTime`.
- **Der Testlauf installiert die App neu** und beendet dabei die laufende Instanz im
  Simulator. Danach landen Tipps auf dem iOS-Home-Bildschirm. Nach `xcodebuild test`
  immer neu starten.
- **Farbeindrücke messen, nicht schätzen.** Ein violetter Schimmer um eine Karte sah
  nach ausgelaufenem Schein aus; die Pixel außerhalb der Karte waren mit und ohne
  Song-Karte identisch. Es waren die Glasflächen selbst. Zwei „Korrekturen" gingen
  dafür drauf, bevor gemessen wurde.

## Was der Nutzer selbst tun muss

**Das alte Spotify-Client-Secret im Dashboard widerrufen.** Es war nie committet
(`Secrets.xcconfig` stand von Anfang an in `.gitignore`), lag aber auf dem Rechner und
in jedem Build bis zum Umbau. Seit der Proxy weg ist, benutzt es nichts mehr.

Fürs Bauen auf dem eigenen iPhone: Apple-ID unter `Xcode → Settings → Accounts`, dann
Team in `project.yml` eintragen (nicht in Xcode — das Projekt wird generiert und
überschreibt es).

## Ungeprüft geblieben

- Der Token-Tausch (`SpotifyTokenExchange`) hat als einziger Task **kein Einzelreview**
  bekommen. Er ist die Stelle, an der sich entscheidet, ob wirklich kein Secret mehr
  rausgeht.
- Der Fix für eine fehlgeschlagene Anmelde-Präsentation (`session.start()` liefert
  `false`) ist nur durch Lesen belegt.
- `KeychainTokenStore` hat keine direkten Tests; das Testziel hat keine Entitlements.
- Barrierefreiheit ist in der ganzen App unangetastet — bis auf einzelne
  `accessibilityLabel` an Icon-Knöpfen.
- Ein **sehr schneller Wisch** im Swipe-Feed hat einmal die Navigation zurückgeschoben
  statt zu blättern. Bei normalem Tempo blättert es zuverlässig, und es ließ sich nicht
  wieder auslösen.
