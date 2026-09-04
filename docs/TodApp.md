---
tags: [todapp, übersicht]
---

# TodApp

Täglich einen Song mit der Gruppe teilen, bewerten, auflösen. SwiftUI, iOS 17,
Swift 6. Prototyp — noch kein Backend, alle Daten im Speicher.

## Entwurf

- [[direction-approved|Richtung (abgenommen)]] — was die App sein soll
- [[brand-spec|Brand-Spec]] — Farben, Schriften, Tonfall
- [[2026-08-28-todapp-swiftui-design|Architektur-Spec]] — Datenmodell, AppStore,
  Repositories, Navigation
- [[2026-08-29-tod-app-music-embeds-design|Musik-Integration: Design]] — Spotify und
  SoundCloud

## Umsetzung

- [[2026-08-29-music-embeds|Musik-Integration: Implementierungsplan]] — 10 Tasks,
  jeder mit Tests
- [[2026-08-29-music-integration-decisions|Entscheidungen der Musik-Integration]] —
  was vom Plan abwich und warum

## Woran gerade gearbeitet wird

**Voting ist echt** (Branch `feat/music-embeds`). Vorher hielt `VotingView` die
Bewertungen nur in lokalem `@State` — nichts erreichte das Repository, und ein
Tab-Wechsel warf die halbe Runde weg. Beide Seiten sind jetzt fertig und im
Simulator durchgespielt:

- `MyVotes` und `RoundScore` in `Core/Models/RoundScore.swift`
- `VoteRepository.fetchMyVotes(voterID:groupID:)` und `fetchRoundScores(groupID:)`
- `AppStore.loadMyVotes()`, plus `castVote`/`toggleHiddenGem`/`submitVotes`, die den
  eigenen Zustand mitführen und `alreadyVoted` als erwarteten Zustand schlucken
- `VotingView` liest und schreibt durch den Store, lädt per `.task(id:currentGroupID)`
  nach und wird nach dem Absenden schreibgeschützt: die getroffene Wahl bleibt
  lesbar, die verworfenen Stufen treten zurück, und statt eines toten Buttons steht
  dort die Bestätigung
- `RevealView` zeigt Rundenpunkte pro Song plus Tagessieger aus
  `[RoundScore].leaders` — bei Gleichstand alle geteilten Spitzenplätze, und vor dem
  eigenen Absenden nur den Hinweis, dass das Ergebnis noch verdeckt ist

Entschieden ist: Saisonpunkte bleiben vorerst außen vor, der Hidden Gem zählt als 💎
ohne Punktwirkung, und das Ergebnis erscheint, sobald **du** abgeschickt hast — nicht
erst wenn alle fertig sind.

Nebenbei repariert: `TodPrimaryButtonStyle` hat `isEnabled` ignoriert, ein
deaktivierter Button sah also voll drückbar aus. Ein Button-Style erreicht
`isEnabled` nur über die Umgebung einer echten View, nicht über sich selbst — daher
die verschachtelte `StyledLabel`.

Für den eigenen Song stimmt man nicht. Entschieden ist die sichtbare Variante: die
eigene Submission bleibt in der Voting-Liste stehen, damit die Runde ihre echte Größe
behält, zeigt aber statt der Bewertungsstufen den Hinweis "Dein Song" und bietet
nichts zum Drücken. Der Abschicken-Button wartet nur auf `votableSubmissions`, also
auf alles außer dem eigenen Beitrag. Die Regel sitzt zusätzlich im Store —
`castVote` und `toggleHiddenGem` weisen die eigene Submission ab —, damit sie nicht
bloß eine Konvention der Oberfläche ist.

Artwork zeigen jetzt alle drei Listen — Suche, Voting, Reveal. Die Suchtreffer
zeichneten das Cover nie, obwohl der Kandidat seine `artworkURL` die ganze Zeit
mitführte, und `VotingView` kannte nur `coverColorHex`. Die Farbe ist überall der
Rückfall, nicht der Entwurf. `BattleView` bleibt außen vor: dort fehlt die
Datengrundlage, `BattleEntry` trägt keine `TrackSource`.

## Wo was liegt

Der **Code** ist in Obsidian nicht sichtbar (Swift-Dateien), liegt aber unter
`TodApp/`: `Core/Models` das Datenmodell, `Core/Music` die Dienst-Anbindungen,
`Core/Repositories` die Datenzugriffs-Protokolle, `Features/<Bereich>` je eine
Ansicht.

Der **Wissensgraph** unter `graphify-out/` ist aus dem Vault ausgeblendet, weil sein
generiertes Wiki die Suche sonst flutet. Abfragen laufen über die Kommandozeile:

```
command graphify query "wie kommt ein geposteter Song zur Wiedergabe"
```

Das vorangestellte `command` ist nötig: Eine Shell-Funktion hängt sonst ein Flag an,
das `graphify update` nicht kennt, und der Aufruf schlägt fehl.

Der **Arbeitsverlauf** der laufenden Umsetzung liegt in
`.superpowers/sdd/2026-08-29-music-embeds/` — Ledger, Task-Briefs, Berichte. Obsidian
blendet Punkt-Ordner aus, und das Verzeichnis wird nach Abschluss gelöscht. Alles,
was davon dauerhaft zählt, steht in
[[2026-08-29-music-integration-decisions|Entscheidungen]].

## Zugangsdaten

`Secrets.xcconfig` im Projektstamm hält Spotify-Client-ID und -Secret. Die Datei ist
in `.gitignore` und war nie in einem Commit. Vorlage mit leeren Werten:
`Secrets.example.xcconfig`. Nach einem frischen Klon:

```
cp Secrets.example.xcconfig Secrets.xcconfig
```

Werte kommen aus dem [Spotify-Dashboard](https://developer.spotify.com/dashboard).
Ohne sie läuft die App, die Suche meldet dann aber im Klartext, dass die Datei
ausgefüllt werden muss.

## Bauen und testen

```
xcodegen generate
xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

`xcodegen generate` ist nach jeder neuen Quelldatei nötig — das Projekt wird aus
`project.yml` erzeugt.
