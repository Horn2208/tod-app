---
tags: [todapp, übergabe]
---

# Übergabe — Stand 11. September 2026, nachts

Alles committet und gepusht. Branch `feat/music-embeds`, **286 Tests grün**, keine
Build-Warnungen. Offener PR:
[soft233-ttv/tod-app#1](https://github.com/soft233-ttv/tod-app/pull/1).

## Was gemacht ist

Der Redesign-Prompt (`docs/2026-09-04-redesign-prompt-home-gruppen-profil.md`) ist
abgearbeitet — Reveal am Kalendertag, Kommentare, Profil, Chat als Gruppen-Hub,
Gruppeneinstellungen mit Einlade-Berechtigung und Saisontabelle, Swipe-Feed mit
Bewertungs-Notizen, Rangliste auf echten Zahlen, und der eigene Spotify-Player über
die iFrame API mit Wellenform.

## Was als Nächstes ansteht

**Eine Sache prüfen, die ich nicht prüfen konnte.** Läuft die 30-Sekunden-Vorschau
einmal durch, soll ein erneuter Druck auf Play sie neu starten. Die Ursache war, dass
`position >= duration` nie zutraf: die letzte Meldung kommt bei 29,998 gegen 30,0 an,
also fiel der Knopf auf `togglePlay` an einem Controller, der nichts mehr umzuschalten
hatte. `hasFinished` erlaubt jetzt eine Dreiviertelsekunde Toleranz — **ob es damit
wirklich neu startet, ist unbestätigt.** Am Bildschirm dauert die Prüfung zwei
Sekunden: Song öffnen, Play, bis 0:30 warten, nochmal Play.

Warum ich es nicht konnte: zwischen einem Tipp und einer Bildschirmaufnahme vergehen
über dreißig Sekunden, also ist die Vorschau jedes Mal vorbei, bevor die nächste
Aufnahme entsteht. Jede „hängt fest"-Beobachtung passt genauso zu einem funktionierenden
Player, der ungesehen durchlief. Wer das hier fortsetzt: **nicht** aus Screenshots auf
den Verlauf einer 30-Sekunden-Wiedergabe schließen.

Danach offen aus dem Prompt: **Apple Music über MusicKit** — braucht den bezahlten
Apple-Developer-Account, liegt also beim Nutzer. SoundCloud bleibt beim Embed-Widget;
für die iFrame API gibt es dort kein Gegenstück.

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
  `CommentTime`, `Waveform`, `Member.hasPosted`.
- **Was sich aus Daten ableiten lässt, wird abgeleitet — nicht daneben gespeichert.**
  Zweimal hat in einer Nacht ein gespeicherter Wert über Mitternacht gelogen: Seed-Zeiten
  als „vor N Stunden" und `Member.hasPostedToday` als Flag, das beim Posten gesetzt und
  nie wieder gelöscht wurde. Beide hängen jetzt am Kalendertag bzw. an `postedDates`,
  so wie `currentStreak` es von Anfang an tat.
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
- **Zeit im Seed gehört an den Kalendertag, nicht an „vor N Stunden".** Die Songs von
  heute standen als `Date().addingTimeInterval(-5400)` im Seed. Um 01:00 ist das der
  Vortag, also rutschten sie in die aufgedeckte Runde: `castVote` antwortete
  `.roundClosed` auf einen Song, den der Voten-Bildschirm noch anbot. Zwei Tests haben
  es gefangen — beim ersten Lauf dieser Suite nach Mitternacht überhaupt.
- **Tests nicht durch ein `grep` hindurch an einen Push hängen.** `xcodebuild test |
  grep ... && git push` pusht auch bei roten Tests, weil das `grep` erfolgreich ist.
  Genau so ging ein roter Stand raus.
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
