# Auftrag für den Code-Agenten: TodApp, Stand 8. Oktober 2026

Lies zuerst `docs/UEBERGABE.md` (Regeln, Fallen, was gebaut ist) und von
`docs/2026-09-04-redesign-prompt-home-gruppen-profil.md` die Abschnitte
„Audit: Design, Performance, Lücken (8. Oktober)“, „Neu: Tipp auf den
Mini-Player …“, „Code kürzer machen“ und „Audit 2: Spielregeln, Bedienung, UI“.
Dort stehen zu jedem Punkt Ist-Zustand, Fundstellen im Code und Begründung.
Diese Datei ist die Arbeitsliste dazu, in der Reihenfolge, in der gebaut wird.

## Regeln (gelten für jeden Punkt)

- Bestehende Architektur nutzen: `AppStore` → Repository-Protokolle →
  `SupabaseRepository` / `InMemoryRepository`. Keine Parallelstrukturen.
  Jede neue Repository-Methode auch in `InMemoryRepository`.
- Design-Tokens aus `Core/DesignSystem/` (`Color.tod…`, `.todDisplay/.todBody/.todMono`),
  keine neuen Farben oder Systemschriften für Text.
- Reine Regeln ohne SwiftUI in eigene Typen und dort testen (Muster:
  `TrackSection`, `RoundVisibility`, `GroupsFeed`, `CommentTime`).
- Oberflächentexte Deutsch, „du“, keine Ausrufezeichen. Code-Kommentare Englisch.
- Kein Knopf ohne Wirkung. VoiceOver-Beschriftung für alles Neue (`Spoken`).
- Neue Tabellen/Spalten nur per Migration unter `supabase/migrations/`,
  RLS für jede neue Tabelle.
- Nach jeder neuen oder gelöschten Datei `xcodegen generate` und die
  `project.pbxproj` mitcommitten.
- Prüfen mit `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`.
  Nicht über ein `grep` an einen Push hängen.
- Ein Commit pro Punkt, Nachricht auf Englisch. Danach in `docs/UEBERGABE.md`
  unter „Was als Nächstes ansteht“ eintragen, was gebaut, was getestet und
  was nur im Code gelesen ist.

## Schon erledigt, nicht noch einmal machen

- Spotify Connect ist ausgebaut (Commit `0ae34ca`, noch ungebaut). Als Erstes
  bauen und testen; erwartet sind weniger Tests als 722, weil Connect-Tests weg sind.

## Nicht anfangen, erst den Nutzer fragen

- **Blinde Bewertung (Audit 2, A1):** Ob bis Mitternacht niemand wissen soll,
  wer welchen Song gepostet hat, ist noch nicht entschieden. Story-Reihe,
  Kommentarnamen und `poster_id` unverändert lassen, bis der Nutzer antwortet.

## Arbeitsliste

### Runde 1: Fehler, die Nutzer heute treffen

1. **Gruppen-Neuladen bei jeder Nachricht** (Audit 1, P1): `fetchGroups()` nur
   laufende + aufgedeckte Runde laden, Abfragen pro Gruppe parallel, Realtime
   gezielt pro Tabelle statt alles neu, eigenes Echo ignorieren, entprellen.
2. **Chat zeigt Absender und Uhrzeit** (Audit 1, P1): `ChatMessage.sentAt`,
   Name über der ersten Blase einer Folge, Avatar, Zeittrenner ab ~15 min.
3. **Chat-Rendering** (Audit 1, P1): `LazyVStack`, Schatten an Glasblasen weg,
   Submissions einmal als Wörterbuch statt Suche pro Nachricht.
4. **„Erinnerung an alle senden“** (Audit 1, P1): Knopf ausblenden, bis es
   echten Push gibt. Keine Erfolgsmeldung ohne Wirkung.
5. **Markenschriften einbinden** (Audit 1, P1): Unbounded, Manrope,
   JetBrains Mono als `.ttf` + `UIAppFonts`, PostScript-Namen prüfen, Test mit
   `UIFont(name:size:)`. Danach Home, Player, Profil auf Abschneiden prüfen.
6. **Rundentag aus Berlin** (Audit 2, A2): `round_day` vom Server ins Modell,
   `RoundVisibility` mit festem `Europe/Berlin`-Kalender. Tests mit anderer Gerätezone.
7. **Mitternacht bei offener App** (Audit 2, A3): auf
   `significantTimeChangeNotification` neu laden; `.roundClosed` im laufenden
   Feed nicht verschlucken, sondern „Die Runde ist vorbei“ mit Weg zum Reveal.

### Runde 2: Bedienung

8. **Gruppenstatus auf Home** (Audit 2, A4): „3 von 5 haben gepostet ·
   2 Songs zu bewerten · Aufdeckung in 6 Std.“ mit Knopf „Jetzt bewerten“.
9. **Mini-Player öffnet immer** (Abschnitt „Neu: Tipp auf den Mini-Player“):
   ganze Kapsel tippbar, Play-Knopf bleibt eigenständig, ohne Post öffnet der
   Player für die laufende Quelle, Zoom-Übergang ab iOS 18, Regel
   `MiniPlayerTarget` mit Tests.
10. **Bewerten optimistisch** (Audit 2, B2): Auswahl und Hidden Gem sofort
    setzen, bei Fehler zurück, haptisches Feedback.
11. **Posten** (Audit 2, B1): Zielgruppe anzeigen und wählbar, „Posten“ mit
    Ladezustand und gesperrt während des Sendens, „Nichts gefunden“-Zustand,
    „Anderen Song wählen“.
12. **Kommentar geht nicht verloren** (Audit 2, B3): als „wird gesendet“
    zeigen, bei Fehler zurück ins Feld.
13. **Gruppenliste** (Audit 2, B4): Zeit relativ (heute Uhrzeit, „gestern“,
    sonst Datum), Vorschau = Neuestes aus Chat oder Song, Punkt für Ungelesenes.

### Runde 3: App-Store-Reife

14. **Löschen, Verlassen, Entfernen** (Audit 2, C): Der Server erlaubt es
    schon (RLS vorhanden). Nur Repository-Methoden + UI: Gruppe verlassen,
    Mitglied entfernen (Ersteller), Gruppe löschen (Ersteller), eigenen Post
    von heute, eigenen Kommentar, eigene Nachricht löschen. Kontextmenü auf
    langem Druck, Bestätigung nennt das Ding beim Namen.
15. **Melden und Blockieren** (Audit 1, P2): Tabellen `reports` und `blocks`
    per Migration, Inhalte Blockierter in `GroupAssembly` ausfiltern.
16. **Gruppeneinstellungen** (Audit 2, B5): Mitgliederliste, „Punkte
    insgesamt“ nur noch in der Rangliste, nach dem Erstellen direkt einladen,
    Emoji-Raster statt Freitext.
17. **Einladen per Link** (Audit 1, P2): `todapp://join/<code>` in `onOpenURL`,
    Beitritt nach der Anmeldung fortsetzen, Link im geteilten Text.
18. **Anonyme Konten sichern** (Audit 2, B6): im Profil „Konto sichern – mit
    Apple verknüpfen“ über Supabase `linkIdentity`.
19. **Anmeldebildschirm** (Audit 2, B7): „Mit Spotify fortfahren“ entfernen
    oder klein darunter (nur fünf Personen können es).
20. **Premium** (Audit 1, P2): Schalter nur in Debug-Builds, „+“-Knopf im
    Chat ausblenden, bis Battle eine Tabelle hat.
21. **Spotify-Limit erklären** (Abschnitt „Spotify-Limit seit Februar/März
    2026“): verständliche Meldung beim Verbinden statt allgemeinem Fehler.

### Runde 4: Aufräumen und Feinschliff

22. **Bilder** (Audit 1, P2): Fotos vor dem Speichern verkleinern, Avatare
    gecacht dekodieren, alle `AsyncImage` für Cover → `CrossfadeCover`.
23. **Code kürzer** (Abschnitt „Code kürzer machen“): `todGlassCard`-Modifier,
    `PlayPress` entdoppeln, `TrackPlayerSheet.swift` und `AppStore.swift` aufteilen.
24. **Kleinigkeiten** (Audit 1, P3 und Audit 2, B8): Tippflächen ≥ 44 pt,
    Cover relativ zur Bildschirmbreite, `.white` in `RootNavBar` → Token,
    „Ehemaliges Mitglied“ statt UUID, Song-Auswahl im Chat im App-Stil mit
    leerem Zustand, „Nochmal“ im Fehlerbanner, Profil in Abschnitte gliedern,
    deutsche Kommentare und leeres `.onChange` in `ChatView` aufräumen.
25. **Später, eigener Auftrag:** echte Push-Benachrichtigungen (APNs + Edge
    Function), Offline-Hinweis, Onboarding.

## Was am Ende jeder Runde zurückkommt

Eine kurze Liste: welche Punkte gebaut sind, welche Tests neu sind, was im
Simulator gesehen wurde und was nur gelesen ist, und alles, wo du vom Brief
abgewichen bist und warum.
