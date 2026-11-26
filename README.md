# TodApp

iPhone-App, in der eine Gruppe jeden Tag einen Song teilt: Jede*r postet einen Song (Spotify oder SoundCloud), die Gruppe bewertet die Songs des Tages, danach folgt die Auflösung mit Rundenpunkten und Saisontabelle. Dazu gibt es Gruppenchat, Kommentare, Streaks und tägliche Erinnerungen. Die App ist durchgehend auf Deutsch. Konten laufen über Sign in with Apple, die Daten liegen in Supabase. Ohne Supabase-Zugangsdaten (und in den Tests) laufen dieselben Bildschirme auf Daten im Speicher.

## Voraussetzungen

- iOS 17.0 als Deployment-Target, nur iPhone (`project.yml`)
- Swift 6.0 (`SWIFT_VERSION` in `project.yml`)
- Xcode; zuletzt gebaut mit Xcode 27.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Swift-Pakete (exakt gepinnt, über SPM): `supabase-swift` 2.55.2, Spotify `ios-sdk` 5.0.1

## Bauen und starten

Das Xcode-Projekt wird aus `project.yml` erzeugt und ist mit eingecheckt. Nach jeder neuen oder gelöschten Quelldatei neu erzeugen und `TodApp.xcodeproj/project.pbxproj` mitcommitten:

```
xcodegen generate
```

Scheme `TodApp`, Ziel zum Beispiel iPhone-17-Simulator. In Xcode `TodApp.xcodeproj` öffnen und starten, oder:

```
xcodebuild build -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

Nur Debug-Builds kennen zwei Startargumente: `-inMemoryData` (Demo-Daten statt Backend) und `-skipSignIn` (überspringt die Anmeldung, es kommen dann keine Server-Daten).

## Konfiguration

Nichts davon ist eingecheckt.

- **Supabase:** `Config/Secrets.example.xcconfig` nach `Config/Secrets.xcconfig` kopieren (steht in `.gitignore`) und `SUPABASE_URL` (`https://<your-supabase-project-ref>.supabase.co`) sowie `SUPABASE_ANON_KEY` eintragen, Werte aus dem Supabase-Dashboard unter Project Settings > API Keys. Nur den öffentlichen Client-Key verwenden, nie `service_role`. Der Build schreibt beide Werte in die Info.plist (`SupabaseURL`, `SupabaseAnonKey`). Fehlt die Datei, baut und startet die App trotzdem, auf Daten im Speicher.
- **Datenbank:** Schema und Änderungen liegen in `supabase/migrations/` (Dateien nach Version benannt), etwa per `supabase db push` oder durch Ausführen der SQL-Dateien in Reihenfolge.
- **Spotify:** Die Client-ID steht als `SpotifyClientID` in `project.yml` (Info-Properties). Sie ist laut Kommentar dort bewusst öffentlich (PKCE, kein Client-Secret). Für einen eigenen Fork die ID der eigenen Spotify-App eintragen und als Redirect-URI `todapp://auth/spotify` im Spotify-Dashboard registrieren.
- **Signing:** `PRODUCT_BUNDLE_IDENTIFIER` und `DEVELOPMENT_TEAM` stehen in `project.yml`. Für einen eigenen Fork anpassen; in Xcode allein gesetzt, gehen sie beim nächsten `xcodegen generate` verloren. Sign in with Apple braucht die passende Capability an der App-ID.

Hinweis zu Spotify: Ganze Songs spielen nur mit angemeldetem Spotify-Premium-Konto, sonst gibt es Spotifys 30-Sekunden-Ausschnitt (siehe Kommentar in `TodApp/Core/Music/Embed/SpotifyEmbedPlayer.swift`).

## Projektstruktur

```
TodApp/            App-Target (SwiftUI)
  App/             Einstieg und Wurzel-Navigation
  Core/            AppStore, Modelle, Repositories (Supabase und InMemory), Musik-Anbindung, Backend, Design-Tokens, Benachrichtigungen
  Features/        Bildschirme: Auth, Battle, Chat, Groups, Leaderboard, Player, PostSong, Profile, Shared, Song, Today
  Resources/Fonts  Schriften (SIL OFL, Lizenzen daneben)
TodAppTests/       Unit-Tests
Config/            xcconfig-Dateien und Vorlage für die Secrets
supabase/          SQL-Migrationen
docs/              Übergabe, Konzepte, Prompts, Screenshots; Einstieg: docs/TodApp.md, aktueller Stand: docs/UEBERGABE.md
tools/             make-app-icon.swift (erzeugt das App-Icon)
project.yml        XcodeGen-Spezifikation
```

## Tests

```
xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

Die Tests laufen ohne Backend auf `InMemoryRepository`.

## Wissensgraph (graphify)

`graphify-out/` ist abgeleitet und nicht eingecheckt. Zum Einstieg `graphify query "<Frage>"`, `graphify path "<A>" "<B>"` oder `graphify explain "<Konzept>"`; nach Codeänderungen `graphify update .`. Eine Übersicht steht in `graphify-out/GRAPH_REPORT.md`.
