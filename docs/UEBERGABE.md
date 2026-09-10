---
tags: [todapp, übergabe]
---

# Übergabe — Stand 10. September 2026

Alles committet und gepusht. Branch `feat/music-embeds`, 81 Commits über `main`,
**235 Tests grün**, keine Build-Warnungen. Offener PR:
[soft233-ttv/tod-app#1](https://github.com/soft233-ttv/tod-app/pull/1).

## Was der nächste Schritt ist

**Die neue Reveal-Regel verdrahten.** `RoundVisibility` liegt fertig und getestet in
`TodApp/Core/Models/RoundVisibility.swift`, ist aber an nichts angeschlossen. Die Regel:
eine Runde wird am *Folgetag* aufgedeckt, nie am selben Tag. Genau deshalb dürfen
Bewertungen den ganzen Tag über änderbar bleiben — es ist nichts zu sehen, also verrät
ein Sinneswandel nichts.

Der Umbau entfernt `hasSubmitted` und `submitVotes()` als sperrenden Mechanismus. Die
Fläche, nach Datei:

| Datei | Stellen |
|---|---|
| `TodAppTests/VotingFlowTests.swift` | 6 |
| `TodApp/Core/AppStore.swift` | 6 |
| `TodApp/Features/Voting/VotingView.swift` | 5 |
| `TodAppTests/InMemoryRepositoryTests.swift` | 2 |
| `TodApp/Core/Repositories/InMemoryRepository.swift` | 2 |
| `TodApp/Features/Reveal/RevealView.swift` | 1 |
| `TodApp/Core/Repositories/VoteRepository.swift` | 1 |
| `TodApp/Core/Models/RoundScore.swift` | 1 |

Achtung: mehrere bestehende Tests sichern die **alte** Regel ab („nach dem Abschicken
gesperrt"). Die müssen mit umgeschrieben werden, nicht gelöscht — sonst verschwindet
die Absicherung mitsamt der Regel.

## Was danach noch aus dem Redesign-Prompt fehlt

Der Prompt liegt in `docs/2026-09-04-redesign-prompt-home-gruppen-profil.md` (der Nutzer
hat ihn zwischendurch überarbeitet — Gruppenzeile öffnet jetzt den Chat als Hub, nicht
mehr eine separate Song-Detail-Ansicht).

- **Kommentaransicht** unter dem Song, mit Eingabefeld. `Comment` (Autor, Zeit) steht im
  Modell, `AppStore` hat aber noch **kein** `addComment` — das Repository schon.
- **Profil-Bildschirm** mit Name und Bild (`UserProfile` liegt im `AppStore`). Er soll
  die Abmeldung aus dem „Mehr"-Tab übernehmen; danach kann der Tab weg.
- **Visuelle Ausrichtung**: Cover-Glow hinter dem Song auf Home, Glasflächen breiter
  eingesetzt.

## Regeln, die dieses Projekt sich gegeben hat

- **Keine Emoji auf Home** (ausdrücklicher Wunsch). SF Symbols stattdessen; die Streak
  trägt `todStreak`, das Notenzeichen `todAccent`. Gruppen-Emoji als Bild-Rückfall
  bleiben davon unberührt.
- Oberflächentexte **auf Deutsch**, informelles „du", keine Ausrufezeichen. Kommentare im
  Code auf Englisch.
- Keine View verzweigt nach Dienstnamen — nur nach `MusicProviderCapabilities`.
- Reine Rechenregeln leben ohne SwiftUI und werden dort getestet: `TrackSection`,
  `Streak`, `GroupsFeed`, `RoundVisibility`.
- Geteilte Test-Helfer gehören in `TodAppTests/TestSupport.swift`. Das musste in diesem
  Projekt schon viermal nachgeholt werden.
- Nach jeder neuen Datei `xcodegen generate` **und** die erzeugte `project.pbxproj`
  mitcommitten. Vier Tasks haben Zeit verloren, weil der Fehler „Typ nicht gefunden"
  lautet, obwohl die Datei danebenliegt.
- Ein Test, der nicht scheitern kann, wird gelöscht statt aufgepolstert. Zwei sind so
  schon geflogen.

## Was der Nutzer selbst tun muss

**Das alte Spotify-Client-Secret im Dashboard widerrufen.** Es war nie committet
(`Secrets.xcconfig` stand von Anfang an in `.gitignore`, eine Suche über alle Commits
nach dem Wert findet nichts), lag aber auf dem Rechner und in jedem Build bis zum
Umbau. Seit der Proxy weg ist, benutzt es nichts mehr — widerrufen statt rotieren.

Fürs Bauen auf dem eigenen iPhone: Apple-ID unter `Xcode → Settings → Accounts`, dann
Team in `project.yml` eintragen (nicht in Xcode — das Projekt wird generiert und
überschreibt es).

## Ungeprüft geblieben

- Der Token-Tausch (`SpotifyTokenExchange`) hat als einziger Task **kein Einzelreview**
  bekommen — drei Anläufe scheiterten an der Infrastruktur, der Nutzer entschied, ihn
  laufen zu lassen. Er ist die Stelle, an der sich entscheidet, ob wirklich kein Secret
  mehr rausgeht.
- Der Fix für eine fehlgeschlagene Anmelde-Präsentation (`session.start()` liefert
  `false`) ist nur durch Lesen belegt — das Testziel hat kein Fenster, um eine
  Fehlpräsentation zu erzwingen.
- `KeychainTokenStore` hat keine direkten Tests; das Testziel hat keine Entitlements.
- Barrierefreiheit ist in der ganzen App unangetastet.

## Zum Arbeiten mit Subagenten in diesem Projekt

Heute sind neun gestorben — fünf an Sitzungslimits, vier an Hängern. Zwei Lehren:
Aufträge sollen **früh committen**, bevor die Sichtprüfung beginnt; und nach jedem
Ausfall lohnt der Blick in den Arbeitsbaum, weil mehrfach fertige Arbeit dort lag und
nur der Abschluss fehlte.
