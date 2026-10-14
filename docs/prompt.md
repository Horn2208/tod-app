# Auftrag für den Code-Agenten: TodApp, Stand 14. Oktober 2026

Zwei neue Funktionen: **(1) Banner auf Home für die Auswertung ab 0 Uhr und
fürs Bewerten** und **(2) ein Verlauf der eigenen Songs im
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

## 1. Banner auf Home: „Gestern ist aufgedeckt“ und „Noch bewerten“

**Wunsch des Nutzers (14. Oktober, präzisiert):** „Bewerten ab jeder Uhrzeit am
Tag, und ab null Uhr die Auswertung als Banner. Und ein Bewertungs-Ding auf dem
Home-Screen, wenn man noch nicht alle bewertet hat.“ Also **kein** automatisches
Öffnen eines Bildschirms, sondern Banner auf Home, die man antippt.

**Ist (geprüft am 14. Oktober):**
- Bewerten geht schon den ganzen Tag: `RoundVisibility.isVotable` prüft nur den
  Berliner Kalendertag, keine Uhrzeit. **So lassen**, nichts an der Regel ändern.
- Ab 0:00 (Berlin) ist gestern aufgedeckt. Home zeigt das nur in der Rundenkarte
  (`TodayView.roundCard`), und zwar erst, wenn nichts mehr zu bewerten ist
  (`else if status.revealed > 0`). Wer heute noch bewerten muss, sieht den
  Hinweis auf gestern gar nicht.
- „Jetzt bewerten“ ist ein Knopf in derselben Rundenkarte ganz unten auf Home,
  unter Serie und eigenem Song. Leicht zu übersehen.

**Soll: zwei Banner ganz oben auf Home**, direkt unter dem Gruppen-Umschalter,
über der Serie. Beide als Glas-Karte (`todGlassCard`), voll breit, ganze Karte
tippbar, rechts ein Chevron. Erscheinen und Verschwinden mit `.snappy` +
`.opacity`/`.move(edge: .top)`, ohne die Seite springen zu lassen.

**Banner A: Auswertung (ab 0:00 bis man sie gesehen hat)**
- Sichtbar, wenn die gewählte Gruppe eine aufgedeckte Runde von gestern hat
  (`store.revealedSubmissions` nicht leer) und dieser Tag hier noch nicht
  angesehen wurde.
- Inhalt: links bis zu drei Cover von gestern überlappend (`CrossfadeCover`,
  32 pt, Radius 8), daneben „Gestern ist aufgedeckt“ (`todBody` 15 bold) und
  darunter dein Ergebnis („Dein Song: 7 Punkte · Platz 2 von 5“, oder
  „5 Songs, sieh dir an, wie bewertet wurde“, wenn du nichts gepostet hast).
  Akzent `todAccent2` (Gold, „Ergebnis“).
- Tipp öffnet `SongFeedView(round: .revealed)` (vorhandenes `isShowingReveal`).
- **Gesehen merken** pro Gruppe und Tag lokal, Muster `ChatReadMarks`
  (`@AppStorage`, Schlüssel mit Gruppen-ID). Gesetzt, sobald die Auflösung
  geöffnet wurde (über Banner oder Rundenkarte). Danach verschwindet Banner A
  bis zum nächsten Tag. Zusätzlich ein kleines „×“ zum Ausblenden ohne Öffnen
  (setzt dieselbe Marke).
- Hat gestern niemand gepostet: kein Banner.
- Andere Gruppen mit ungesehener Auswertung: kleiner Punkt (`todAccent2`) an
  ihrem Kreis in `GroupSwitcherBar`.

**Banner B: Noch bewerten (den ganzen Tag, solange etwas offen ist)**
- Sichtbar, solange `HomeToday.status(...).toRate > 0` (heutige Songs der
  anderen, die du noch nicht bewertet hast). Unabhängig davon, ob du selbst
  schon gepostet hast.
- Inhalt: Cover der noch unbewerteten Songs (bis zu drei, überlappend), Text
  „2 Songs warten auf deine Bewertung“ bzw. „1 Song wartet …“, darunter klein
  „Änderbar bis Mitternacht“. Akzent `todAccent` (Pink, Handlung).
  Fortschritt als schmaler Balken unten in der Karte („3 von 5 bewertet“).
- Tipp öffnet `SongFeedView(round: .running)` **an der ersten unbewerteten
  Karte** (`startAt:` gibt es schon).
- Verschwindet von selbst, sobald alles bewertet ist (Werte kommen aus
  `store.myVotes`, das nach dem Bewerten sofort aktualisiert wird).
- Kommt im Laufe des Tages ein neuer Song dazu (Realtime), erscheint B wieder.

**Beide gleichzeitig** (morgens gestern ungesehen und heute schon Songs da):
A oben, B darunter.

**Rundenkarte unten aufräumen:** Ihre Knöpfe „Jetzt bewerten“ und „Gestern ist
aufgedeckt“ übernehmen jetzt die Banner. Die Karte zeigt nur noch die
Statuszeile („3 von 5 haben gepostet · Aufdeckung in 6 Std.“), ohne Knopf,
damit nichts doppelt da ist.

**In der Auflösung oben eine Zusammenfassung** als erste Seite (nur
`round: .revealed`, nur wenn ohne `startAt` geöffnet): „Gestern in <Gruppe>“,
Tagesrangliste (Platz, Cover klein, Titel, Name, Punkte, 💎) aus
`store.roundScores`, eigene Zeile hervorgehoben, darunter „Wischen für alle
Bewertungen“. Eine Seite im bestehenden Seiten-Feed (`containerRelativeFrame`).
UEBERGABE-Falle beachten: Seiten-Feed nicht zu einer späteren Karte scrollen;
die Zusammenfassung ist einfach die erste Seite.

**Reine Regeln mit Tests** (neu `Features/Today/HomeBanners.swift`):
- `HomeBanners.banners(status:revealedDay:lastSeenRevealDay:) -> [Banner]`
  (keiner / nur A / nur B / A + B in dieser Reihenfolge).
- `HomeBanners.resultLine(scores:submissions:me:)` → „Dein Song: 7 Punkte ·
  Platz 2 von 5“, Gleichstand = gleicher Platz, eigener Song fehlt.
- `HomeBanners.rateLine(toRate:)` → Einzahl/Mehrzahl.
- Erste unbewertete Karte für `startAt`.

**Barrierefreiheit:** jedes Banner ein Knopf mit einem Satz, z. B. „Gestern ist
aufgedeckt. Dein Song: 7 Punkte, Platz 2 von 5. Öffnet die Auswertung.“ bzw.
„2 Songs warten auf deine Bewertung. Öffnet die Bewertung.“ Das „×“ als eigener
Knopf „Hinweis ausblenden“.

**Im Simulator prüfen:** Gruppe mit Posts von gestern → Banner A oben → Tipp →
Zusammenfassung, dann Karten → zurück → Banner A weg, auch nach Neustart.
Heute Songs anderer da → Banner B mit Anzahl → Tipp → erste unbewertete Karte →
alle bewerten → zurück → Banner B weg. Rundenkarte unten ohne Knöpfe.

Betroffen: `Features/Today/TodayView.swift`, `Features/Today/HomeToday.swift`,
`Features/Today/GroupSwitcherBar.swift`, `Features/Song/SongFeedView.swift`,
neu `Features/Today/HomeBanners.swift` (+ Tests), `Spoken`.

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

Erst **1** (sofort spürbar, jeden Tag), dann **2**. Jeweils bauen, Tests,
Simulator, UEBERGABE nachtragen, Commit.

## Was am Ende zurückkommt

Eine kurze Liste: was gebaut ist, welche Tests neu sind, was im Simulator
gesehen wurde und was nur gelesen ist, Screenshots von beiden Bannern, der Zusammenfassung und dem
Kalender nach `docs/screenshots/`, und alles, wo du vom Auftrag abgewichen
bist und warum.
