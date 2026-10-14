# Auftrag für den Code-Agenten: TodApp, Stand 14. Oktober 2026

Zwei neue Funktionen: **(1) Am nächsten Tag öffnet Home von selbst die
Auflösung von gestern** und **(2) ein Verlauf der eigenen Songs im
Streak-Kalender**. Die alte Arbeitsliste (Runden 1–4 vom 8./9. Oktober) ist
erledigt; sie steht in Git (`git log -- docs/prompt.md`) und in
`docs/UEBERGABE.md` unter „Was als Nächstes ansteht“.

Lies zuerst `docs/UEBERGABE.md` (Regeln, Fallen, was gebaut ist).

## Regeln (gelten für jeden Punkt)

- Bestehende Architektur nutzen: `AppStore` (samt Extensions) → Repository-Protokolle →
  `SupabaseRepository` / `InMemoryRepository`. Keine Parallelstrukturen.
  Jede neue Repository-Methode auch in `InMemoryRepository`.
- Design-Tokens aus `Core/DesignSystem/` (`Color.tod…`, `.todDisplay/.todBody/.todMono`),
  Glas-Karten über `.todGlassCard(radius:)`, Cover über `CrossfadeCover`/`CoverImages`.
- Reine Regeln ohne SwiftUI in eigene Typen und dort testen (Muster:
  `HomeToday`, `RoundVisibility`, `StreakCalendar`, `GroupsFeed`).
- Rundentage immer im Berliner Kalender (`RoundDay.berlinCalendar`), nie `Calendar.current`.
- Oberflächentexte Deutsch, „du“, keine Ausrufezeichen. Code-Kommentare Englisch.
- Kein Knopf ohne Wirkung. VoiceOver-Beschriftung für alles Neue (`Spoken`).
- Nach jeder neuen oder gelöschten Datei `xcodegen generate` und die
  `project.pbxproj` mitcommitten.
- Prüfen mit `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`.
  Nicht über ein `grep` an einen Push hängen.
- Ein Commit pro Punkt, Nachricht auf Englisch. Danach in `docs/UEBERGABE.md`
  unter „Was als Nächstes ansteht“ eintragen, was gebaut, was getestet und
  was nur im Code gelesen ist.

---

## 1. Am nächsten Tag: Home öffnet die Auflösung von gestern

**Wunsch des Nutzers (14. Oktober):** „Ich möchte, dass am nächsten Tag direkt
auf Home der Bewertungsscreen kommt, mit dem, was bewertet wurde.“

**Ist (geprüft am 14. Oktober):** Nach Mitternacht (Berlin) ist die Runde von
gestern aufgedeckt. Home zeigt das nur als Zeile in der Rundenkarte
(`TodayView.roundCard`, Knopf „Gestern ist aufgedeckt“, sichtbar erst wenn
nichts mehr zu bewerten ist) und öffnet dann `SongFeedView(round: .revealed)`.
Von selbst passiert nichts; wer es nicht sucht, sieht die Ergebnisse nie.

**Soll:**

1. **Einmal pro Tag und Gruppe von selbst.** Kommt Home zum ersten Mal an einem
   neuen Berliner Tag in den Vordergrund und hat die gewählte Gruppe eine
   aufgedeckte Runde von gestern (`store.revealedSubmissions` nicht leer), die
   hier noch nicht gesehen wurde, schiebt Home automatisch
   `SongFeedView(round: .revealed)` auf seinen `NavigationStack` (derselbe Weg
   wie `isShowingReveal`). Zurück führt auf Home.
2. **„Gesehen“ lokal merken**, pro Gruppe der zuletzt gesehene Rundentag, nach
   dem Muster von `ChatReadMarks` (`@AppStorage`, Schlüssel mit Gruppen-ID).
   Gesetzt wird er, sobald die Auflösung erscheint, egal ob von selbst oder
   über den Knopf. Gilt pro Gerät; kein Server nötig.
3. **Nicht dazwischenfunken.** Kein automatisches Öffnen, wenn gerade ein Sheet
   offen ist (Posten, Song, Profil, Kalender), wenn etwas auf Home gepusht ist,
   wenn die Seite „Gruppen“ aktiv ist, oder wenn die App über einen
   Einladungslink geöffnet wurde. Dann beim nächsten ruhigen Erscheinen von Home
   (Gruppe gewechselt, App wieder vorn).
4. **Mehrere Gruppen:** nur für die gewählte. Hat eine andere Gruppe eine
   ungesehene Auflösung, zeigt `GroupSwitcherBar` an ihrem Kreis einen kleinen
   Punkt (`todAccent2`); Wechsel dorthin öffnet ihre Auflösung nach Regel 1.
5. **Oben in der Auflösung eine Zusammenfassung** als erste Karte, bevor die
   Song-Karten kommen (nur `round: .revealed`): „Gestern in <Gruppe>“, darunter
   die Tagesrangliste (Platz, Cover klein, Titel, Name, Punkte, 💎) aus
   `store.roundScores`, die eigene Zeile hervorgehoben, und ein Satz zum
   eigenen Song („Dein Song: 7 Punkte, Platz 2 von 5“, oder „Du hattest gestern
   nichts gepostet“). Darunter „Wischen für alle Bewertungen“. Die Karte ist
   eine Seite im bestehenden Seiten-Feed (`containerRelativeFrame`), damit das
   Blättern gleich bleibt. Achtung UEBERGABE-Falle „Seiten-Feed nicht zu einer
   späteren Karte scrollen“: Die Zusammenfassung ist einfach die erste Seite;
   `startAt` aus der Story-Reihe oder dem Chat überspringt sie (dann kommt die
   gewünschte Karte zuerst, wie bisher).
6. **Leer:** Hat gestern niemand gepostet, öffnet nichts von selbst (der leere
   Zustand bleibt nur über den Knopf erreichbar).

**Reine Regel mit Tests:** `RevealIntro.shouldOpen(lastSeenDay:revealedDay:revealedCount:isQuiet:) -> Bool`
und `RevealIntro.summary(scores:submissions:me:) -> Summary` (Platz, Punkte,
eigene Zeile, Gleichstand = gleicher Platz). Fälle: erster Start, gleicher Tag
zweimal, neuer Tag, Gruppe ohne gestrige Posts, eigener Song fehlt, Gleichstand.

**Im Simulator prüfen:** Datum der Seed-Daten bzw. Uhr so stellen, dass gestern
eine Runde hat → App öffnen → Auflösung erscheint mit Zusammenfassung → zurück
→ App in den Hintergrund und wieder vorn → erscheint nicht noch einmal. Gruppe
mit ungesehener Auflösung zeigt Punkt im Umschalter.

Betroffen: `Features/Today/TodayView.swift`, `Features/Today/GroupSwitcherBar.swift`,
`Features/Song/SongFeedView.swift`, neu `Features/Today/RevealIntro.swift`
(+ Tests), ggf. `Features/Shared/Spoken…`.

---

## 2. Verlauf: die eigenen Songs im Streak-Kalender

**Wunsch des Nutzers (14. Oktober):** „Man soll seine History angucken können:
auf die Streak klicken, dann die Tage anklicken und seinen Song sehen, oder da
ist direkt das Cover des Songs.“

**Ist (geprüft am 14. Oktober):** Tipp auf die Serie auf Home öffnet
`StreakCalendarView` (Monat für Monat). Gepostete Tage sind ein oranger Kreis
(`TodayView.streakSheen`), die Zellen sind nicht antippbar. Der View bekommt nur
`postedDates` und `currentStreak`, keine Songs. Die Daten wären da:
`fetchGroups()` lädt weiterhin die ganze Geschichte jeder Gruppe in
`group.submissions` (die Begrenzung auf zwei Runden wurde in Runde 1 bewusst
nicht umgesetzt, siehe UEBERGABE).

**Soll:**

1. **Cover statt Kreis.** Jeder Tag, an dem du in der gewählten Gruppe
   gepostet hast, zeigt das Cover deines Songs als kleines abgerundetes Quadrat
   (Zelle ~38 pt, Cover ~34 pt, Radius 8) mit der Tageszahl klein unten links
   auf einem dunklen Verlauf, damit sie auf jedem Cover lesbar bleibt. Ohne
   Cover-Adresse die Songfarbe (`coverColorHex`) als Fläche. Tage ohne Post
   bleiben wie jetzt (Zahl, gedimmt), heute behält den `todAccent`-Ring.
   Die Serie bleibt erkennbar: aufeinanderfolgende gepostete Tage bekommen einen
   feinen `todStreak`-Rahmen (1 pt) statt der orangen Fläche. Legende anpassen.
2. **Tag antippen → dein Song an dem Tag.** Öffnet ein Sheet mit:
   - Datum als Titel („Dienstag, 6. Oktober“),
   - `SongDetailView` für diesen Song (Player + Kommentare wie überall),
   - darüber, sobald die Runde aufgedeckt ist, das Ergebnis des Tages: Punkte,
     Platz in der Gruppe, 💎, und die Bewertungen der anderen mit Begründung
     (gleiche Darstellung wie `VoteRow` im Reveal). Geladen beim Öffnen über die
     vorhandenen `voteRepo.fetchRoundScores(groupID:day:)` und
     `voteRepo.fetchVotes(groupID:day:)` (RLS erlaubt Stimmen für vergangene
     Tage). Für heute: „Wird um Mitternacht aufgedeckt.“
   Tage ohne Post sind nicht antippbar (kein Knopf ohne Wirkung).
3. **Darunter eine Liste „Deine Songs im <Monat>“**: pro geposteten Tag eine
   Zeile (Datum, Cover, Titel, Künstler, Punkte, falls aufgedeckt), neueste
   zuerst, Tipp öffnet dasselbe Sheet. Für alle, die lieber scrollen als im
   Raster tippen, und für VoiceOver der bequemere Weg.
4. **Pro Gruppe.** Der Kalender zeigt wie bisher die gewählte Gruppe (Serie und
   `postedDates` sind pro Gruppe). Titel „Deine Serie in <Gruppe>“.
5. **Daten über eine Stelle holen**, nicht direkt aus `group.submissions` im
   View: neue Funktion im Store, z. B. `store.mySongs(in groupID:) -> [Date: Submission]`
   (Schlüssel = Berliner Tagesanfang). Heute liest sie aus `group.submissions`.
   So muss später nur diese Funktion auf eine eigene schmale Abfrage
   (`fetchMySubmissions(groupID:posterID:)`) umgestellt werden, falls
   `fetchGroups()` irgendwann doch nur zwei Runden lädt.
6. **Performance:** bis zu 31 Cover pro Monat. `CoverImages` cacht schon; nur
   die sichtbaren Monate laden (Monatswechsel lädt nach), Zellen lazy.
   Ein Seitenwischen zwischen Monaten wäre schön (wie `TabView(.page)`),
   die Pfeile bleiben für VoiceOver.

**Barrierefreiheit:** Zelle mit Post = Knopf, gelesen als „6. Oktober,
Blinding Lights von The Weeknd, öffnet den Song“. Ohne Post wie bisher
„6. Oktober, nicht gepostet“.

**Reine Regeln mit Tests** (in `StreakCalendar`): Tag → Song-Zuordnung im
Berliner Kalender (Post um 23:59 Berlin zählt zum selben Tag, auch bei
Gerätezone ≠ Berlin), Seriengrenzen für den Rahmen (welche Tage zu einer
zusammenhängenden Serie gehören), Monatsliste neueste zuerst, Ergebnis-Zeile
„7 Punkte · Platz 2 von 5“.

**Im Simulator prüfen:** Serie antippen → Cover in den geposteten Tagen →
Tag antippen → Song spielt, Kommentare da, Ergebnis mit Bewertungen der
anderen → heute antippen → „Wird um Mitternacht aufgedeckt“ → Monat zurück
blättern → Cover laden nach. Mit großer Systemschrift prüfen, dass die
Tageszahl nicht das Cover sprengt.

Betroffen: `Features/Today/StreakCalendarView.swift`,
`Features/Today/StreakCalendar.swift`, `Features/Today/TodayView.swift`
(übergibt Gruppe statt nur Daten), `Core/AppStore*.swift` (`mySongs`),
neu `Features/Today/HistoryDaySheet.swift` (+ Tests).

---

## Reihenfolge

Erst **1** (kleiner, sofort spürbar), dann **2**. Jeweils bauen, Tests,
Simulator, UEBERGABE nachtragen, Commit.

## Was am Ende zurückkommt

Eine kurze Liste: was gebaut ist, welche Tests neu sind, was im Simulator
gesehen wurde und was nur gelesen ist, Screenshots von Zusammenfassung und
Kalender nach `docs/screenshots/`, und alles, wo du vom Auftrag abgewichen
bist und warum.
