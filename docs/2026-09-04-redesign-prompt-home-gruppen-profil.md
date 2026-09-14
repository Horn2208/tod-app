# Prompt: TodApp – Redesign Home, Gruppen-Ansicht, Profil, Mini-Player

Kopier diesen Prompt komplett in codex-cli / gemini-cli (oder eine andere Coding-KI).
Er enthält den nötigen Kontext zum bestehenden Code, damit die KI nicht raten muss.

---

## Kontext

Das ist **TodApp**, ein SwiftUI-Prototyp (iOS 17, Swift 6). Grundidee: täglich
einen Song mit der Gruppe teilen, bewerten, auflösen. Architektur: `AppStore`
(zentraler `@Observable` State) → Repository-Protokolle → aktuell
`InMemoryRepository` (alle Daten nur im Speicher). Views liegen unter
`TodApp/Features/<Bereich>/`, Datenmodelle unter `TodApp/Core/Models/`, Design-Tokens
unter `TodApp/Core/DesignSystem/`. **Update:** es gibt jetzt einen echten
Supabase-Server (Postgres + Auth + Realtime + Storage) – Ziel ist, neben
`InMemoryRepository` eine `SupabaseRepository` zu bauen, die dasselbe
Repository-Protokoll erfüllt, siehe neuer Abschnitt 7 unten. `InMemoryRepository`
bleibt bestehen (für SwiftUI-Previews/Unit-Tests weiterhin sinnvoll), wird aber
für den echten Betrieb durch `SupabaseRepository` ersetzt.

**Design-System, unbedingt weiterverwenden statt neu zu erfinden:**
- Farben: `Core/DesignSystem/Color+Tokens.swift` – `.todBackground`, `.todSurface`,
  `.todSurface2/3`, `.todLine`, `.todText`, `.todTextDim`, `.todTextFaint`,
  `.todAccent` (#b3527a, Pink), `.todAccent2` (#e0b64a, Gold), `.todGood` (Grün).
- Schriften: `Core/DesignSystem/Font+Tokens.swift` – `.todDisplay()` (Unbounded, für
  große Überschriften), `.todBody()` (Manrope, Fließtext), `.todMono()` (JetBrains
  Mono, für Meta-Infos wie Zeitstempel/Tags).
- Bestehende Buttons/Komponenten wiederverwenden, z.B. `TodPrimaryButtonStyle` aus
  `Features/Today/TodayView.swift`.

**Aktueller Stand, den dieser Prompt verändert:**
- `App/RootTabView.swift`: `TabView` mit Heute/Voten/Reveal/Rangliste/Chat/Battle,
  darüber ein `GroupSwitcher` (horizontale Pill-Liste zum Gruppenwechsel).
- `Features/Today/TodayView.swift`: zeigt Gruppenname, Mitglieder-Avatare (nur
  Initialen-Kreise, keine echten Profilbilder), Post-Status. Kein Song-Player, kein
  Streak.
- `Features/Chat/ChatView.swift`: einfacher Gruppenchat, kein Bezug zu Songs.
- `Features/Player/TrackPlayerSheet.swift` + `TrackEmbedView.swift`: Song-Player ist
  ein `WKWebView` mit Spotify/SoundCloud-Embed (`allowsInlineMediaPlayback`,
  `mediaTypesRequiringUserActionForPlayback = .all`). **Wichtig:** laut Code-Kommentar
  ist jede `TrackEmbedView`-Instanz ein eigener Web-Prozess – nie in eine Liste
  einbetten, und für einen persistenten Mini-Player darf **nicht** bei jedem
  Öffnen/Schließen eine neue `WKWebView` erzeugt werden (sonst stoppt die Wiedergabe).
  Die WebView muss beim Schließen des Kommentar-Sheets als **eine** Instanz erhalten
  bleiben (z.B. über einen App-weiten `PlayerManager`/State in `AppStore`, den Mini-
  Player und Voll-Ansicht gemeinsam nutzen), nicht neu instanziiert werden.
  **Wichtige Kursänderung (siehe 3g weiter unten):** `TrackEmbedView` wird nicht
  mehr der Hauptweg für Wiedergabe – neue primäre Quelle ist Apple Music über
  natives `MusicKit`, `TrackEmbedView` bleibt nur noch als Fallback bestehen.
- `Core/Models/`: `Group` (id, name, icon, members, submissions, board,
  chatMessages, activeBattle), `Member` (id, name, isCurrentUser, hasPostedToday –
  **kein Streak-Feld bisher**), `Submission` (track, artist, posterID, coverColorHex,
  `comments: [String]` – **keine Autoren/Zeitstempel bisher**, source, section).
- Es gibt aktuell **kein** Profil-Feature (kein eigener Name/Profilbild/Account-
  Screen) und **keine echten Profilbilder** (nur Initialen in Kreisen).

Die zwei angehängten Screenshots zeigen die Instagram-Referenz: Screenshot 1 = obere
Story-Leiste + darunter die Chat-/Ordner-Liste. Screenshot 2 = aufgeklappte Ansicht
mit großem Kommentarbereich, normal großem Player oben, Antwort-Feld unten.

---

## Aufgabe

Baue drei Bereiche der App neu bzw. um. Halte dich an bestehende Architektur
(`AppStore`, Repository-Pattern, Design-Tokens) statt Parallelstrukturen zu bauen.

### 1. Neue Default-Seite ("Home" / bisher "Heute")

Ersetzt bzw. ersetzt den Inhalt von `TodayView.swift`. Ziel: sofort sichtbar sein
sollen groß

- der **heute bereits gepostete Song** der eigenen Gruppe (großes Cover/Artwork,
  Titel, Artist, eingebetteter Player – wiederverwende `TrackEmbedView`/
  `TrackPlayerSheet`-Logik statt sie zu duplizieren), und
- die **Tages-Streak** (wie viele Tage in Folge gepostet wurde) – prominent, z.B. als
  große Zahl mit Flamme/Icon.

Für die Streak fehlt aktuell ein Datenfeld. Ergänze es sinnvoll im Modell (z.B.
`currentStreak: Int` auf `Member` oder `Group`, plus die Logik, wie sie berechnet/
hochgezählt wird beim Posten) und in `InMemoryRepository` mit Beispieldaten.

Wenn heute noch nicht gepostet wurde, bleibt der bestehende "+ Song posten"-Zustand
(via `PostSongView`) erhalten, aber ebenfalls großzügiger/prominenter gestaltet statt
als kleine Zeile.

**Neu: Tippen auf die Streak öffnet eine Wochen-/Kalender-Ansicht.** Antippt man die
Streak-Zahl/Flamme, öffnet sich eine Ansicht (z.B. `Features/Home/StreakCalendarView.swift`),
die wie ein Kalender rückwärts durch die Wochen blättern lässt und pro Tag zeigt, ob
gepostet wurde (ähnlich Duolingos Streak-Kalender). Dafür reicht das reine
`currentStreak: Int` nicht – es braucht zusätzlich eine Historie pro Tag (z.B. ein
`postedDates: Set<Date>`/`[Date]` auf `Member`, oder aus den vorhandenen
`Submission`-Zeitstempeln abgeleitet, gefiltert auf den aktuellen Nutzer).

**Neu: Bewerten findet auch direkt auf dem Home-Screen statt.** Nachdem man den
eigenen Song gepostet hat (über `PostSongView`), geht es auf Home direkt weiter zum
**Song-Swipe-Feed** (siehe Punkt 3c) – Bewerten ist also nicht nur über den
Gruppen-Chat erreichbar, sondern schließt sich nahtlos ans eigene Posten auf Home an.
Der Swipe-Feed selbst bleibt dieselbe eine Komponente (kein zweiter, eigener
Bewertungs-Screen nur für Home) – Home und Chat sind nur zwei verschiedene
Einstiegspunkte in dieselbe Ansicht.

**Neu: eleganter Gruppen-Switcher auf Home.** Wer in mehreren Gruppen ist, braucht
auf Home eine Möglichkeit zu wechseln, welche Gruppe (Song + Streak) gerade
angezeigt wird. Die bisherige `GroupSwitcher`-Komponente aus `RootTabView.swift` ist
dafür bewusst schlicht gehalten – nur Text in Kapseln (`Label(group.name, ...)` in
`Color.todSurface2`). Für Home ersetzen durch etwas, das zum "Modern
Premium"-Abschnitt passt: eine horizontale Reihe der **Gruppen-Profilbilder als
Kreise** (nutzt das neue `Group`-Profilbild-Feld aus Abschnitt 2) statt Text-Pillen –
die aktuell ausgewählte Gruppe hervorgehoben, z.B. mit demselben
Story-Ring-Gradient (`todAccent` → `todAccent2`) wie bei den Story-Bubbles in der
Gruppen-Ansicht, die anderen kleiner/gedimmt (`opacity` reduziert). Dahinter weiter
`store.selectGroup(id)` wie bisher, nur wechselt jetzt zusätzlich auch der groß
gezeigte Song + die Streak auf Home entsprechend der gewählten Gruppe. Eigene
Komponente, z.B. `Features/Home/GroupSwitcherBar.swift`, mit Glas-Hintergrund
(`.ultraThinMaterial` + `todLine`-Rand) statt der bisherigen `Color.todSurface2`
Kapseln. Ob die alte `GroupSwitcher`-Leiste über der Tab-Leiste in `RootTabView`
dafür komplett entfällt oder daneben bestehen bleibt, hängt von der weiter unten
ohnehin offenen Root-Tab-Entscheidung ab – aber mindestens auf Home ersetzt dieser
neue, elegantere Switcher die alte Pillen-Optik.

### 2. Gruppen-Ansicht (Instagram-Style)

Neue View (z.B. `Features/Groups/GroupsFeedView.swift`), Instagram-DM-Screen als
Vorbild (siehe Screenshot 1):

- **Oben**: horizontale Story-Leiste mit Kreis-Avataren – zeigt, wer heute schon
  gepostet hat (ähnlich der bestehenden `AvatarBadge`-Logik in `TodayView`, aber als
  eigene Komponente mit echtem Profilbild statt nur Initialen, plus Ring/Hervorhebung
  wenn gepostet wurde). **Präzisierung (siehe drittes Screenshot, Instagrams
  "Now Listening"-Bubble über `jan.lbg`):** Über dem Avatar erscheint eine kleine,
  farbige Sprechblase mit Songtitel + Artist des geposteten Songs (statt nur eines
  Rings) – jede Person, die heute gepostet hat, bekommt also ihre eigene
  Song-Bubble über dem Namen. **Tippen öffnet direkt den Song-Swipe-Feed (Punkt 3c),
  aufgeklappt bei genau der Karte dieser Person** – jede Person wird dabei
  einzeln/separat bewertet und kommentiert (weiterhin: maximal ein Kommentar pro
  Person und Song, siehe Punkt 3c) – nicht den Chat und nicht eine eigene separate
  Song-Ansicht, sondern denselben Swipe-Feed wie überall sonst, nur mit einer
  bestimmten Startposition.
- **Darunter**: Liste der Tod-Gruppen als Zeilen im Stil einer Chat-Liste (analog zu
  Instagrams Chat-Liste unterhalb der Ordner-Tabs) – pro Zeile: Gruppen-Profilbild,
  Gruppenname, der zuletzt gepostete Song als Vorschau-Text, Uhrzeit rechts (wie ein
  Chat-Preview mit Zeitstempel). **Tippen auf eine Zeile öffnet direkt den Chat
  dieser Gruppe** (siehe Punkt 3 – nicht mehr eine separate Song-Detail-Ansicht wie
  in einer früheren Version dieses Dokuments; der Chat selbst ist jetzt der
  Einstiegspunkt und Hub der Gruppe).
- Gruppen brauchen dafür ein **Profilbild-Feld** (aktuell nur `icon: String` als
  Emoji/Symbol) – ergänze echte Bildauswahl/-anzeige (z.B. `imageData`/`imageURL` auf
  `Group`, mit Fallback auf das bestehende `icon`, falls kein Bild gesetzt ist).

### 3. Gruppen-Chat als Hub (Battle-Sheet, Rangliste, Song-Swipe-Feed, Gruppeneinstellungen)

**Präzisierung/Update:** Statt einer separaten Song-Detail-Ansicht ist der
**Gruppen-Chat** (`ChatView.swift`, überarbeitet) jetzt der zentrale Ort pro Gruppe.
Von dort aus sind vier Dinge erreichbar:

**a) Battle über ein "+" in der Eingabeleiste.** Rechts neben dem bestehenden
Nachrichten-Textfeld in `ChatView` kommt ein "+"-Button dazu. Tippen öffnet ein
Bottom-Sheet mit Aufschieb-Animation (`.sheet` mit `.presentationDetents`, analog zum
bestehenden `TrackPlayerSheet`-Pattern), über das man ein Battle in dieser Gruppe
startet (Einstieg in `BattleView`/`BattleRepository`). Battle bleibt dabei das
Premium-Feature aus dem Monetarisierungs-Abschnitt unten – im "+"-Sheet entsprechend
gesperrt/mit Hinweis zeigen, wenn der Nutzer kein Premium hat.

**b) Rangliste als eigener, auffälliger Button** (nicht als normaler Tab) – z.B. ein
Icon-Button in der Navigationsleiste des Chats, der die bestehende
`LeaderboardView` öffnet. "Special" bedeutet hier: visuell hervorgehoben (z.B. mit
dem Gold-Akzent `todAccent2` oder einem eigenen Badge), damit er sich von normalen
Chat-Aktionen abhebt.

**c) Song-Swipe-Feed statt separater Voten-/Reveal-Tabs.** Von hier aus (z.B. über
ein eigenes Icon im Chat oder automatisch, wenn eine neue Runde ansteht) öffnet sich
ein vertikales Swipe-Format: man scrollt/swiped nach unten durch die heute geposteten
Songs, jeweils mit großem Cover, kann den Song abspielen und darunter die Kommentare
sehen – sowohl die aller (öffentlich) als auch die eigenen. Das übernimmt die
Aufgabe von `VotingView` und `RevealView`, nur im Swipe-Karten-Format statt als Liste.
**Korrigierte Reveal-Logik (wichtig, weicht vom bisherigen `AppStore`-Verhalten ab):**
Am Tag des Postens selbst sieht **niemand irgendeine Bewertung – auch nicht die
eigene**. Man kann an dem Tag posten und die Songs des Tages bewerten, die Bewertung
bleibt dabei frei änderbar (kein "Absenden sperrt den eigenen Vote", solange der Tag
noch läuft) – **genau deshalb** zeigt die App an dem Tag noch nichts an: es soll ja
noch geändert werden können. Erst am **nächsten Tag** wird die Runde des Vortags
komplett aufgedeckt – alle Bewertungen aller Mitglieder, die eigene eingeschlossen,
gemeinsam als ein Reveal-Moment.

Der Tages-Rhythmus ist also rollierend: an jedem Tag passiert gleichzeitig (1) das
Posten + freie Bewerten der **heutigen** Songs (noch nichts sichtbar, weiter
änderbar) und (2) das **Reveal der gestrigen** Runde (jetzt final und einsehbar,
inklusive aller Bewertungen und der zugehörigen Bewertungs-Kommentare). Das heißt für
den Song-Swipe-Feed: er zeigt pro Tag die aufgedeckte Runde von **gestern**, nicht
die von heute – der heutige Tag taucht darin frühestens morgen auf.

Das ist eine echte Logik-Änderung gegenüber dem bestehenden `AppStore`/
`VoteRepository`: aktuell hängt die Freigabe des Ergebnisses am eigenen
`hasSubmitted`-Flag (siehe `submitVotes()`, `RevealView`/`PendingVoteNotice`) – jeder
sieht sein Ergebnis, sobald er selbst abgeschickt hat, unabhängig vom Kalendertag.
Neu: die Freigabe hängt am **Kalendertag der Runde**, nicht mehr an einem manuellen
Absenden – `hasSubmitted`/`submitVotes()` als sperrender Schritt entfällt, Bewertungen
sind den ganzen Tag über frei änderbar (`castVote` einfach wiederholt aufrufbar), und
`roundScores`/das Reveal für eine Runde werden erst ab dem Folgetag geladen bzw.
angezeigt (z.B. über einen Vergleich von `Submission`-Datum und aktuellem Datum statt
über `myVotes.hasSubmitted`).

**Korrektur/Vereinfachung: nur EIN Kommentar pro Person und Song, und der ist immer
an die Bewertung gekoppelt.** Kein separates, offenes Kommentar-System mit beliebig
vielen Einträgen pro Song – jede Person kann zu jedem Song genau einen Kommentar
abgeben, und dieser Kommentar ist die Begründung zur eigenen Bewertung (z.B. warum
sie den Song hoch/niedrig bewertet hat), kein allgemeiner Diskussions-Kommentar.
Damit reicht die reine `comments: [String]`-Liste auf `Submission` nicht mehr, wird
aber auch nicht durch eine unbegrenzte `Comment`-Struktur ersetzt, sondern durch ein
optionales `note`-Textfeld direkt an `Vote` (ein `Vote` pro Person und Song existiert
im `AppStore` ohnehin schon über `castVote`/`myVotes.ratings`, das erzwingt die
Ein-Kommentar-Regel praktisch von selbst, weil ein erneuter `castVote`-Aufruf für
denselben Song den bisherigen Eintrag einfach ersetzt statt einen neuen hinzuzufügen).
`Submission.comments: [String]` kann damit entfallen – die Kommentare hängen jetzt an
`Vote`, nicht mehr an `Submission`. Sichtbar werden diese Kommentare wie beschrieben
erst mit dem Reveal am nächsten Tag, zusammen mit der zugehörigen Bewertung.

**d) Gruppeneinstellungen über einen Button oben im Chat-Fenster.** Öffnet einen
neuen Screen (z.B. `Features/Chat/GroupSettingsView.swift`) mit: Gruppenbild und
-name (bearbeitbar), einer Einstellung dazu **wer neue Mitglieder hinzufügen darf**
(z.B. alle Mitglieder vs. nur der Ersteller – dafür fehlt aktuell ein
Rollen-/Berechtigungsfeld im `Group`/`Member`-Modell, das ergänzt werden muss), und
weiter unten die **Gesamt-Punktzahlen aller Mitglieder** (Season-/Summen-Score über
alle bisherigen Runden – aktuell gibt es dafür laut `docs/TodApp.md` bewusst noch
keine Saisonpunkte-Logik, das wäre hier also die erste Stelle, an der sowas gebraucht
wird; kann fürs Prototyp-Stadium eine einfache Summe der bisherigen `RoundScore`-
Punkte pro Mitglied sein).

**e) Song-Erwähnung im Chat.** Beim Schreiben einer Chat-Nachricht soll man einen
heute geposteten Song erwähnen/referenzieren können (ähnlich einer @-Erwähnung, nur
für Songs statt Personen) – die Nachricht zeigt dann eine kleine eingebettete
Song-Karte (Cover, Titel, Artist) statt nur Text, tippen darauf öffnet den
Song-Swipe-Feed bei genau diesem Song (wie bei den Story-Bubbles). Dafür braucht
`ChatMessage` ein zusätzliches optionales Feld, z.B. `mentionedSubmissionID: Int?`,
plus eine kleine Auswahl-UI beim Schreiben (z.B. ein "🎵"-Button neben dem
Textfeld/im "+"-Sheet aus a), der eine Liste der heutigen Songs zum Auswählen zeigt).

**f) Premium-Feature: Erinnerungs-Broadcast an die ganze Gruppe.** Über das
"+"-Sheet aus a) zusätzlich zu Battle: eine Aktion, mit der man **allen
Gruppenmitgliedern auf einmal** eine Erinnerungs-Benachrichtigung schicken kann
(z.B. "Denk dran, deinen Song zu posten!") – das ist wie Battle ein
Premium-Feature (siehe Monetarisierungs-Abschnitt unten, dort entsprechend
ergänzen). Technisch eine lokale/Push-Notification an die anderen Mitglieder;
fürs Prototyp-Stadium ohne echtes Backend reicht ein simulierter Versand
(z.B. ein Banner/eine In-App-Meldung bei den anderen, kein echter Push nötig).

**g) Musik-Architektur (aktualisiert – wichtige Kursänderung): Apple Music wird
die primäre Quelle für Suche, Posten und Wiedergabe; Spotify dient nur noch als
optionaler Such-/Link-Import.** Grund für die Änderung: Spotify hat im Februar
2026 seinen Entwickler-Zugang stark verschärft (Development Mode auf 5
autorisierte Nutzer:innen begrenzt, mehr nur mit registrierter Firma + 250k MAU),
und volle Song-Wiedergabe über ein Embed/WebView funktioniert laut Spotify
ohnehin nur im Desktop-Browser, nie in einer nativen App – beides zusammen macht
Spotify für "voller Song für eine echte Freundesgruppe" strukturell ungeeignet.
Apple Music hat keine vergleichbare Nutzer-Deckelung.

Der neue Ablauf beim Posten (`PostSongView`):
1. Suche/Link-Einfügen bleibt für beide Quellen möglich – Spotify-Suche läuft
   weiter über den Client-Credentials-Flow (App-Token, kein Login, unlimitiert
   nutzbar, da nicht personenbezogen autorisiert), genauso eine direkte
   Apple-Music-Suche über `MusicKit`.
2. Aus den Metadaten des gefundenen Tracks wird die **ISRC** genommen (bei
   Spotify-Ergebnissen `external_ids.isrc`, bei Apple-Music-Ergebnissen liegt sie
   direkt vor).
3. Mit dieser ISRC wird gegen den offiziellen Apple-Music-Endpoint **"Get
   Multiple Catalog Songs by ISRC"** abgeglichen und die passende
   Apple-Music-Track-ID ermittelt – zuverlässiger als Titel/Artist-Textvergleich,
   weil Remixes/Live-Versionen/Neuauflagen nicht verwechselt werden.
4. Die gefundene Apple-Music-Track-ID wird auf `Submission` gespeichert (neues
   Feld, z.B. `appleMusicID: String?`); wurde über einen Spotify-Link/-Suche
   gepostet, zusätzlich der ursprüngliche `spotifyURL: String?` rein zur Anzeige/
   Attribution (siehe Quellen-Icons unten), nicht zur Wiedergabe.
5. **Kein Match gefunden** (Katalog-Lücke zwischen den Diensten): Fallback auf
   den bisherigen `TrackEmbedView`/`EmbedURLBuilder`-Weg mit Spotifys/SoundClouds
   eigenem Embed-Widget – mit dessen bekannten Limitierungen (nur 30s-Vorschau in
   der nativen App, siehe oben), aber immer noch besser als gar keine Wiedergabe.

**Wiedergabe läuft damit im Regelfall komplett nativ über `MusicKit`/
`ApplicationMusicPlayer`** gegen den gematchten Apple-Music-Track – für alle
Nutzer:innen einheitlich, kein WebView mehr nötig. Login läuft über die normale
System-Berechtigung (`MusicAuthorization.request()`, ein iOS-Berechtigungsdialog,
kein Web-Login); für den vollen Song braucht die hörende Person weiterhin ein
aktives Apple-Music-Abo, ohne Abo (oder ohne erteilte Berechtigung) läuft
automatisch die Apple-Music-Vorschau aus dem Katalog-Feld `previews`
(historisch ca. 90 Sekunden bei längeren Songs, als Fallback zusätzlich die
offene iTunes-Search-API) – **ganz ohne Login, für beliebig viele Nutzer:innen,
da Apple hierfür keine Nutzer-Autorisierung verlangt.**

Kurz geprüft und bewusst **nicht** verwendet: **Deezer** (Nutzungsbedingungen
verbieten kommerzielle Nutzung explizit – passt nicht zu den geplanten
Premium-Features) und die **YouTube-iFrame-API** (Googles Richtlinien verbieten,
etwas vor den YouTube-Player/seine Controls zu legen – würde dem eigenen,
cleanen Mini-Player-Design widersprechen, plus zusätzliches Nutzungsrisiko, weil
der eigentliche Zweck der App nicht "YouTube-Videos ansehen" ist).

Für SoundCloud gibt es weiterhin kein ISRC-Äquivalent zum Matching – dafür bleibt
vorerst der bestehende Embed-Weg bestehen, bis entschieden wird, ob SoundCloud
als Quelle überhaupt erhalten bleibt.

**h) Quellen-Icons auf dem Mini-Player (dringend/neu).** Weil Wiedergabe jetzt
grundsätzlich über Apple Music läuft, aber Songs weiterhin über einen
Spotify-Link/-Suche gefunden werden können, zeigt der Mini-Player (und die
Song-Karte im Swipe-Feed/auf Home) **kleine Quellen-Icons**, klein und dezent am
Rand, nicht im zentralen "clean" Bereich um den Play/Pause-Button:
- **Apple-Music-Icon immer sichtbar**, da die Wiedergabe technisch immer darüber
  läuft.
- **Zusätzlich ein Spotify-Icon**, wenn dieser Song ursprünglich über einen
  Spotify-Link/-Suche gefunden wurde (`spotifyURL` gesetzt) – zeigt der Person
  transparent "gefunden über Spotify, gespielt über Apple Music".
Dafür die offiziellen Marken-Assets/Badges von Apple ("Apple Music Identity
Guidelines") bzw. Spotify ("Spotify Design"-Richtlinien) verwenden statt eigene
Icons nachzubauen – beide Anbieter haben feste Vorgaben, wie ihr Logo neben
fremden Inhalten dargestellt werden darf/muss.

**i) Song-Abschnitt beim Posten wählen.** Beim Posten wählt die postende Person
zusätzlich **ab welcher Sekunde ihr Song beim Voten starten soll** (Slider/
Scrubber über die Songdauer aus den Metadaten). Neues Feld auf `Submission`, z.B.
`startSeconds: Int = 0`. Diese Auswahl können alle treffen, unabhängig vom
eigenen Abo-Status – Posten und Abschnitt-Wählen ist nie gesperrt.

Ob der gewählte Abschnitt beim Voten dann auch tatsächlich hörbar ist, hängt vom
Abo-Status der **hörenden** Person ab, nicht mehr an Spotify-Premium gekoppelt:
- **Mit aktivem Apple-Music-Abo:** voller Song über `MusicKit` verfügbar, die App
  seekt beim Start der Wiedergabe direkt zu `startSeconds` – die Person hört
  genau den vom Poster gewählten Teil.
- **Ohne Abo:** nur die Apple-Music-Vorschau (fester, von Apple gewählter
  Ausschnitt, ca. 90 Sekunden) steht zur Verfügung – `startSeconds` lässt sich
  nur innerhalb dieses Vorschau-Fensters anwenden, liegt der gewählte Punkt
  außerhalb, wird stattdessen einfach der Anfang der Vorschau gespielt. In der UI
  entsprechend kennzeichnen (gewählten Zeitpunkt anzeigen, ohne ihn als garantiert
  hörbar zu versprechen), statt so zu tun, als würde er sicher abgespielt.

**Mini-Player-Verhalten bleibt wie zuvor beschrieben (wichtig, siehe
Architektur-Hinweis ganz oben):** Egal ob der Song-Swipe-Feed oder ein einzelner Song
im Chat geschlossen wird, während er noch spielt – unten in der App erscheint ein
persistenter Mini-Player mit Pause-Taste, **nur solange** ein Song aktiv spielt
(nicht permanent sichtbar). Tippen auf den Mini-Player öffnet die Stelle wieder, an
der der Song lief. Dafür weiterhin ein App-weiter Player-Zustand (`AppStore` oder
eigener `@Observable`-`PlayerManager`) – die WebView darf dabei wie schon
beschrieben nicht neu erzeugt werden, sonst stoppt die Wiedergabe.

**Form und Platzierung des Mini-Players (Korrektur):** Statt einer schmalen,
vollbreiten Leiste, die unten am Bildschirmrand klebt, ein **freistehendes
abgerundetes Rechteck** (`RoundedRectangle(cornerRadius: 20)` o.ä., Glas-Look wie im
"Glas statt Fläche"-Abschnitt unten: `.ultraThinMaterial` + `todLine`-Rand +
weicher Schatten) mit seitlichem Abstand zum Bildschirmrand, **nicht** als
`.safeAreaInset(edge: .bottom)` direkt über der Tab-Bar/dem unteren Hub platziert,
sondern schwebend mit Abstand darüber – der Player darf das untere Hub/die Tab-Bar
nicht verdecken, sondern muss klar erkennbar darüber liegen (z.B. per `.overlay`
auf dem `RootTabView`-Container mit zusätzlichem Bottom-Padding, statt per
`safeAreaInset`, das den restlichen Inhalt sonst zusätzlich nach oben schieben und
dabei doch am Hub kleben würde). Der Play/Pause-Button darin ist **visuell
hervorgehoben** statt ein normales kleines Icon: größer, mit eigenem
`todAccent`-Farbkreis/Gradient-Hintergrund als Buttonfläche, deutlich vom Rest des
Mini-Players (Cover, Songtitel/Artist, Progressbar) abgesetzt.

**Update – sehr clean, Play/Pause-Button mittig:** Statt einer klassischen
Player-Zeile (Cover links, Text daneben, Play-Button ganz rechts) ein **reduziertes,
zentriertes Layout**: der Play/Pause-Button sitzt **horizontal in der Mitte** des
Mini-Players als klarer optischer Mittelpunkt (`HStack` mit `Spacer()` links/rechts
um den Button, oder Cover/Songtext dezent im Hintergrund und der Button per
`ZStack` mittig darüber gelegt), nicht seitlich an den Rand gedrängt. "Clean"
heißt hier: möglichst wenig gleichzeitig sichtbare Elemente – Cover-Art (klein,
z.B. als dezenter, leicht abgedunkelter Hintergrund im Rechteck statt als
eigenständige separate Kachel) plus der zentrale Play/Pause-Button reichen;
Songtitel/Artist-Text und Progressbar nur sehr dezent (kleine Schrift, geringer
Kontrast) oder ganz weglassen und stattdessen nur als feinen Fortschrittsring **um**
den Play/Pause-Button selbst andeuten (ähnlich einer Ladeanimation) – dadurch bleibt
der Button klar der Blickfang und der Mini-Player wirkt aufgeräumt statt vollgepackt.

**Kurze Ausblend-Verzögerung bei Pause:** Bisher galt "nur sichtbar solange aktiv
gespielt wird" strikt sofort. Neu: Beim Pausieren bleibt der Mini-Player noch für
einen kurzen Moment sichtbar (z.B. 3–5 Sekunden, per `Task { try? await
Task.sleep(...); ... }` oder einem einfachen Timer im `PlayerManager`) und
verschwindet erst danach, statt sofort beim Pausieren zu verschwinden – falls in
der Zwischenzeit wieder auf Play gedrückt wird, bleibt er natürlich weiter sichtbar
und der Timer wird zurückgesetzt/abgebrochen.

**Hinweis:** Die frühere Idee, Spotify komplett eigen über die iFrame API
(`EmbedController`) als Haupt-Wiedergabeweg zu bauen, ist durch Punkt 3g oben
ersetzt (Apple Music als primäre Wiedergabe, Spotify nur noch Such-/Link-Import).
`TrackEmbedView`/`EmbedURLBuilder` bleiben als reiner Fallback bestehen, für den
Fall, dass kein Apple-Music-Match gefunden wird oder SoundCloud als Quelle genutzt
wird.

### 4. Profil-Button oben rechts

Auf Home und/oder in einer neuen Root-Navigationsleiste: Button oben rechts (Icon
z.B. Profilbild-Kreis oder `person.circle`). Öffnet einen Profil-Screen
(`Features/Profile/ProfileView.swift`) mit:

- eigenem Namen (bearbeitbar)
- eigenem Profilbild (auswählen/ändern, z.B. `PhotosPicker`)
- Account-Einstellungen (Platzhalter reicht fürs Prototyp-Stadium, z.B. Logout-
  Button-Stub, keine echte Auth nötig)

Dafür braucht der aktuelle Nutzer ein eigenes Profil-Datenmodell (aktuell nur
`currentUserID = "du"` als String in `AppStore`, `Member.isCurrentUser` als Flag) –
ergänze ein `UserProfile`-Model (Name, Profilbild) und eine Ablage dafür (Repository
oder direkt in `AppStore`, passend zum bestehenden In-Memory-Pattern).

### 5. UX-Detail: Tastatur-Verhalten bei Suche und Chat

Zwei kleine, aber wichtige Verhaltens-Details, die an mehreren Stellen gelten:

- **Song-Suche (`PostSongView`, Suchfeld für `MusicSearchRepository`-Ergebnisse):**
  Drückt man Enter/Return und die Suche liefert ein Ergebnis, soll die Tastatur
  automatisch verschwinden (z.B. `.submitLabel(.search)` mit `.onSubmit { ...;
  isSearchFieldFocused = false }`, oder direkt beim Erhalt der ersten Treffer
  `@FocusState` zurücksetzen).
- **Chat-Eingabefeld (`ChatView`, und jedes andere Textfeld mit sichtbarer
  Tastatur, z.B. das Antwortfeld im Song-Swipe-Feed):** Tippen **irgendwo oberhalb
  der Tastatur außer auf das Textfeld selbst** soll die Tastatur schließen – nicht
  nur ein X-Button oder "Fertig", sondern ein Tap auf die restliche Fläche. In
  SwiftUI z.B. über ein unsichtbares `Color.clear.contentShape(Rectangle())` über
  dem Scroll-Bereich mit `.onTapGesture { isInputFocused = false }`, oder knapper
  `.scrollDismissesKeyboard(.interactively)`/`.immediately` auf der `ScrollView`,
  kombiniert mit `@FocusState` für das Textfeld selbst (damit ein Tap direkt ins
  Feld die Tastatur nicht versehentlich mit schließt).

Gilt sinngemäß überall, wo in dieser App eine Tastatur eingeblendet wird, nicht nur
an den zwei explizit genannten Stellen.

### 6. Tägliche Erinnerungen (lokale Benachrichtigungen)

Die App soll zwei feste tägliche Erinnerungen verschicken, unabhängig vom
Broadcast-Feature aus Punkt 3e:

- **15:00 Uhr:** Erinnerung zu posten – aber **nur, wenn die Person heute noch
  nicht gepostet hat** (`hasPostedToday == false` prüfen, sonst keine
  Benachrichtigung).
- **20:00 Uhr:** Erinnerung zu voten/bewerten – geht an alle, unabhängig vom
  eigenen Post-Status.

Technisch über `UNUserNotificationCenter` mit täglich wiederkehrenden
`UNCalendarNotificationTrigger`-Anfragen (Berechtigung vorher über
`requestAuthorization` einholen, z.B. beim ersten App-Start oder in einem
Onboarding-Schritt). Da ein Calendar-Trigger keinen dynamischen Inhalt zur
Zustellzeit prüfen kann, für die 15:00-Erinnerung am einfachsten: die Anfrage wird
jeden Tag neu geplant, und sobald jemand postet, wird die für **heute** bereits
geplante Anfrage sofort wieder entfernt (`removePendingNotificationRequests`) –
damit kommt die Erinnerung nicht mehr an, wenn längst gepostet wurde.

### 7. Backend-Anbindung über Supabase (neu)

**Wichtige Kursänderung:** Es gibt jetzt einen echten Supabase-Server – TodApp
muss also nicht mehr zwingend rein In-Memory bleiben. Ziel ist **nicht**, die
gesamte App-Logik umzubauen, sondern die bestehende Repository-Architektur zu
nutzen, für die sie eigentlich schon gemacht ist: eine neue
`SupabaseRepository` (z.B. `Core/Repositories/SupabaseRepository.swift`), die
genau dasselbe Repository-Protokoll erfüllt wie `InMemoryRepository`, sodass
`AppStore` und alle Views unverändert bleiben – nur die Datenquelle wechselt.
`InMemoryRepository` **nicht löschen**, sondern für SwiftUI-Previews und
Unit-Tests weiter verwenden (typischer Vorteil des Repository-Patterns).

**Tabellen-Schema (Vorschlag, 1:1 abgeleitet aus den bestehenden Swift-Models):**
- `groups` (id, name, icon, image_url, …)
- `members` (id, group_id, name, is_current_user-Äquivalent entfällt durch
  echten Auth-User, current_streak, posted_dates, role/permission-Feld aus
  Punkt 3d)
- `submissions` (id, group_id, poster_id, track, artist, artwork_url,
  cover_color_hex, source, section, start_seconds, apple_music_id, spotify_url,
  created_at)
- `votes` (id, submission_id, member_id, rating, note) – ein Eintrag pro
  Person und Song, siehe Punkt 3c
- `chat_messages` (id, group_id, sender_id, text, mentioned_submission_id,
  created_at)
- `board_entries`/Season-Scores (id, group_id, member_id, points, round_date)
  für die Gesamt-Punktzahlen aus Punkt 3d
- `user_profiles` (id = Supabase-Auth-User-ID, name, avatar_url, is_premium)

**Auth wird dadurch jetzt sinnvoll möglich (Kurskorrektur zu den Nicht-Zielen
unten):** Der bisherige `currentUserID = "du"`-Stub kann durch echten
**Supabase Auth** ersetzt werden – z.B. Sign in with Apple oder Magic-Link
per E-Mail, beides von Supabase Auth nativ unterstützt. Das ist jetzt mit sehr
wenig Zusatzaufwand möglich, weil der Server eh da ist – kein Muss fürs erste
Umsetzen, aber sinnvoll, sobald mehrere echte Personen auf echten Geräten
mitmachen sollen, statt alles auf einem Gerät zu simulieren.

**Realtime für den Chat:** `ChatView` kann über Supabase Realtime (Postgres-
Changes-Subscription) neue Nachrichten/Reveal-Updates live empfangen, statt zu
pollen oder manuell zu refreshen – passt gut zum "Gruppen-Chat als Hub"-Konzept
aus Abschnitt 3.

**Storage für Profil-/Gruppenbilder:** Ersetzt die bisherige
Nur-lokal-Einschränkung (siehe Nicht-Ziele) – `PhotosPicker` bleibt für die
Auswahl, das ausgewählte Bild wird aber zusätzlich in einen Supabase-Storage-
Bucket hochgeladen, damit Profil-/Gruppenbilder für alle Mitglieder sichtbar
sind, nicht nur lokal auf einem Gerät.

**Sicherheits-Hinweise, unbedingt beachten:**
- **Row Level Security (RLS)** in Supabase für jede Tabelle aktivieren, damit
  z.B. nur Mitglieder einer Gruppe deren `submissions`/`chat_messages` lesen/
  schreiben können – nicht einfach alles offen lassen, nur weil es ein
  Studi-Projekt ist.
- Supabase-URL und **Anon-Key nicht hart in den Code/ins Repo committen**,
  sondern über eine `.xcconfig`-Datei oder `Info.plist`-Eintrag einbinden, die
  in `.gitignore` steht (der Anon-Key ist zwar clientseitig gedacht und durch
  RLS abgesichert, gehört aber trotzdem nicht offen ins Git-Repo, falls das
  Repo später mal öffentlich wird).

Für den Push-Broadcast aus Punkt 3f (bisher "simulierter Versand, kein echter
Push nötig") wäre mit dem Server jetzt auch ein echter Push über eine Supabase
Edge Function + APNs möglich – das ist aber ein größerer Zusatzaufwand
(APNs-Zertifikat/-Key einrichten), daher als spätere Ausbaustufe markiert, kein
Teil des ersten Umsetzungsschritts.

---

## Visuelle Ausrichtung – "Modern Premium"

Die bestehende Palette (dunkler Hintergrund, Pink als Hauptakzent, Gold als
zweiter Akzent, Grün für "erledigt") ist schon der richtige Ausgangspunkt für
einen hochwertigen Look. Für das Redesign gezielt ergänzen statt neu erfinden:

**Neue/erweiterte Farb-Tokens in `Color+Tokens.swift`:**
- `todStreak` – warmes Orange-Rot (z.B. `#ff7a45`) exklusiv für die Tages-Streak
  (Flamme + Zahl auf der Home-Seite). Nicht Gold oder Pink wiederverwenden – Gold
  liest sich als Auszeichnung/Highscore, Pink ist der Marken-Akzent, die Streak
  braucht ihr eigenes "Feuer".
- Story-Ring um die Avatare (wer heute gepostet hat): kein neuer Einzelton,
  sondern ein `AngularGradient` aus `todAccent` → `todAccent2` (Pink zu Gold) statt
  Instagrams Orange-Lila-Verlauf – bleibt in der eigenen Marke.
- Like/Herz-Farbe in den Kommentaren: `todAccent` direkt wiederverwenden statt
  eines neuen Rots – es gibt noch kein reines Rot im System, und Herzen in
  Markenfarbe wirken konsistenter.
- Mini-Player-Hintergrund: nicht `todBackground` (verschwindet), sondern
  `todSurface2`/`todSurface3` kombiniert mit `.ultraThinMaterial`, plus ein
  dünner oberer Rand in `todLine`, damit er sich klar vom Rest abhebt.

**Cover-Art-Glow als Hintergrund:** Auf der Home-Seite hinter dem großen
geposteten Song die dominante Farbe aus dem Album-Cover (`artworkURL`) extrahieren
und stark verwischt (`.blur(radius: 60)`) als weichen Farbverlauf hinter die Karte
legen, `todBackground` bleibt darunter die Basis. Macht jede Song-Karte optisch
einzigartig statt immer gleich pink/gold – der Trick aus Apple Music/Spotify
"Now Playing".

**Glas statt Fläche:** Karten, Mini-Player und Bottom-Sheets (Kommentar-Ansicht,
`TrackPlayerSheet`) nicht als flache `todSurface`-Fläche, sondern mit
`.ultraThinMaterial` + hauchdünnem `todLine`-Rand + weichem Schatten. Wirkt
sofort hochwertiger, weil der Hintergrund leicht durchschimmert.

**Chat ebenfalls "hervorgehoben" statt flach (Interpretation, bitte
gegenprüfen):** Gemeint sind vermutlich die einzelnen Chat-Nachrichten in
`ChatView` – aktuell vermutlich schlichte Farb-Bubbles. Neu: Nachrichten-Bubbles
als abgerundete Rechtecke (`RoundedRectangle(cornerRadius: 18)`, wie iMessage es
mit seinen Sprechblasen macht – dort allerdings mit Blasenschwanz, hier passender
zum Rest der App ohne Schwanz, dafür mit demselben Glas-Look wie oben: eigene
Bubble farblich abgesetzt in `todAccent`-Gradient, fremde Bubbles in
`todSurface2`/`.ultraThinMaterial`), statt flacher einfarbiger Flächen. Dieselbe
abgerundete Rechteck-Optik gilt auch für das Chat-Eingabefeld unten (Punkt 5) und
für die eingebettete Song-Karte bei Erwähnungen (Punkt 3e) – ein durchgängiges
"abgerundetes Rechteck mit Tiefe" als wiederkehrende Form, statt pro Element eine
andere Form zu erfinden.

**Gradient statt Flat-Fill bei Zahlen/Icons:** Streak-Zahl und
Leaderboard-Krone/Spitzenplatz nicht in einer Flat-Farbe, sondern mit einem
feinen `LinearGradient` (`todAccent2` → helles Gold/Weiß) als `.foregroundStyle`
– dezent metallisch statt platt eingefärbt.

**Konsequente Zurückhaltung:** großzügiger Weißraum, pro Screen nur wenige
gleichzeitig sichtbare Akzentfarben, keine bunten Badges nebeneinander. Der
"Premium"-Eindruck kommt eher aus dem sparsamen Einsatz der drei Akzente
(Pink/Gold/Streak-Orange) als aus zusätzlichen Farben.

---

## Offene Design-Entscheidung – bewusst dir überlassen

**Aktualisiert:** Die Navigationsfrage ist inzwischen größtenteils geklärt (siehe
Abschnitt 3 oben): Voten/Reveal werden zum Song-Swipe-Feed, Rangliste wird ein
eigener Button im Chat plus Summen-Ansicht in den Gruppeneinstellungen, Battle
kommt über das "+"-Sheet in der Chat-Eingabeleiste und bleibt Premium-gated. Damit
bleibt die Frage der Root-Tab-Leiste selbst offen: Braucht `RootTabView` überhaupt
noch eine klassische `TabView` mit mehreren Reitern, wenn Home und Gruppen-Ansicht
die zwei Hauptseiten sind und alles Gruppenbezogene jetzt im Chat gebündelt ist? Naheliegend wäre nur noch zwei
Reiter (Home, Gruppen) plus der Profil-Button oben rechts – triff diese Entscheidung
und begründe sie kurz. Wichtig ist nur: keine bestehende Funktion (Posten, Voten/
Reveal, Rangliste, Chat, Battle) soll ohne Ersatz verschwinden, auch wenn sie jetzt
an einer anderen Stelle in der Navigation sitzt als vorher.

---

## Monetarisierung – Idee für den ersten Launch

Kein Werbemodell – die App lebt von der engen, privaten Freundesgruppen-Vibe
(täglicher Song, Streak, Voting), das würde durch Ads kaputtgehen. Stattdessen
Freemium, gestaffelt für den Launch:

- **Battle ist von Anfang an ein Premium-Feature.** `Features/Battle/BattleView.swift`
  bzw. der neue Einstiegspunkt dorthin (siehe offene Navigations-Entscheidung oben)
  wird für Free-Nutzer gesperrt gezeigt (z.B. mit Schloss-Icon + kurzem Hinweis
  "Mit Premium freischalten"), nicht komplett versteckt – sichtbar aber gesperrt
  verkauft die Funktion besser, als wenn niemand weiß, dass es sie gibt. Das ist der
  erste konkrete Kaufanreiz beim Launch, weil Battle ohnehin noch die unfertigste
  Funktion ist (laut `docs/TodApp.md`: "`BattleView` bleibt außen vor, dort fehlt
  die Datengrundlage") – die Premium-Sperre kann parallel zur weiteren
  Battle-Entwicklung eingeführt werden.
- **Erinnerungs-Broadcast an die ganze Gruppe ist ebenfalls Premium** (siehe
  Abschnitt 3f) – die Aktion im "+"-Sheet neben Battle, mit der man allen
  Mitgliedern auf einmal eine Erinnerung schickt ("Denk dran zu posten!"), ist ab
  Launch genauso gesperrt/mit Hinweis gezeigt wie Battle.
- Alles andere (Heute/Home, Posten, Voten, Reveal, Rangliste, Chat, Gruppen-Ansicht)
  bleibt beim Launch komplett kostenlos, damit eine ganze Freundesgruppe ohne
  Kaufhürde mitmachen kann – die App lebt davon, dass alle Mitglieder mitziehen.
- Spätere Ausbaustufen für ein "Tod Premium"-Abo (nicht Teil des ersten Launches,
  aber als Richtung im Hinterkopf): Streak-Freeze als Einzelkauf, die neuen
  visuellen Premium-Skins/Themes aus dem Abschnitt "Modern Premium" oben (Cover-Art-
  Glow-Varianten, andere Story-Ring-Farben als Pink/Gold), und Cosmetics für
  Kommentare/Reaktionen. Battle bleibt dabei dauerhaft Teil von Premium, nicht nur
  ein Launch-Türöffner.
- Technische Umsetzung fürs Prototyp-Stadium: reicht ein einfacher
  `isPremium: Bool`-Flag am `UserProfile`-Model (siehe Profil-Abschnitt oben), noch
  ohne echten In-App-Kauf/StoreKit – die Sperre in der UI soll aber schon jetzt so
  gebaut werden, dass sie später nur an einen echten Kauf-Status angebunden werden
  muss statt die Views nochmal umzubauen.

---

## Nicht-Ziele / Out of Scope

- **Aktualisiert (siehe neuer Abschnitt 7):** Es gibt jetzt einen echten
  Supabase-Server – "kein Backend" gilt also nicht mehr uneingeschränkt.
  `InMemoryRepository` bleibt aber für Previews/Tests bestehen, und ein
  eigenes Login-System muss trotzdem nicht komplett neu erfunden werden:
  Supabase Auth (Sign in with Apple/Magic-Link) übernimmt das, statt dass
  TodApp selbst Passwörter/Accounts verwaltet. Zusätzlich weiterhin echte,
  notwendige Logins gegenüber Dritten: die native Apple-Music-Berechtigung
  (`MusicAuthorization.request()`) gegenüber Apple. Spotify braucht für
  Suche/Import gar keinen Nutzer-Login (siehe 3g, Client-Credentials-Flow).
- **Musik-Quelle aktualisiert (wichtig, siehe 3g):** Apple Music ist jetzt die
  primäre Wiedergabe-Quelle (über `MusicKit`, sobald der bezahlte
  Apple-Developer-Account aktiv ist). Spotify bleibt als Such-/Link-Quelle
  erhalten, wird aber über ISRC-Matching auf den passenden Apple-Music-Track
  abgebildet, statt selbst wiederzugeben. SoundCloud und der bisherige
  `TrackEmbedView`-Embed-Weg bleiben als Fallback, falls kein Apple-Music-Match
  gefunden wird. Deezer und die YouTube-iFrame-API wurden geprüft und bewusst
  nicht verwendet (siehe 3g – Nutzungsbedingungen bzw. Design-Konflikt).
- **Kein Abo-Zwang:** Ein Apple-Music-Abo ist **nicht** Voraussetzung, um die App
  zu nutzen – ohne Abo läuft automatisch die Apple-Music-Vorschau (bzw. iTunes-
  Search-API als Fallback) im selben, eigenen Player, mit Abo der volle Song.
  Posten und Song-Abschnitt auswählen (siehe 3i) funktioniert für alle gleich –
  nur ob der gewählte Abschnitt beim Voten auch tatsächlich hörbar ist, hängt vom
  Abo-Status der jeweiligen Person ab, nicht das Wählen selbst.
- **Aktualisiert:** Profilbilder waren ursprünglich als rein lokale
  Platzhalter-Assets bzw. `PhotosPicker`-Auswahl ohne Server-Upload gedacht –
  mit dem jetzt vorhandenen Supabase-Server werden sie stattdessen in einen
  Supabase-Storage-Bucket hochgeladen (siehe Abschnitt 7), damit alle
  Gruppenmitglieder dieselben Bilder sehen.

## Nach der Umsetzung

- `xcodegen generate` ausführen (Projekt wird aus `project.yml` erzeugt, nötig nach
  jeder neuen Datei).
- Bestehende Konventionen beibehalten: reine Logik (z.B. Streak-Berechnung) wo
  möglich ohne SwiftUI testen, wie es `TrackSection` und `LeaderboardView.barFraction`
  vormachen.
- `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
  zum Prüfen.
- Supabase-Zugangsdaten (URL + Anon-Key) sind gesetzt und **nicht** im Git-Repo
  eingecheckt (siehe Sicherheits-Hinweise in Abschnitt 7); RLS-Policies sind
  für jede neue Tabelle aktiv, bevor mit echten Nutzerdaten getestet wird.
