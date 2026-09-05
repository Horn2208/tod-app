# Prompt: TodApp – Redesign Home, Gruppen-Ansicht, Profil, Mini-Player

Kopier diesen Prompt komplett in codex-cli / gemini-cli (oder eine andere Coding-KI).
Er enthält den nötigen Kontext zum bestehenden Code, damit die KI nicht raten muss.

---

## Kontext

Das ist **TodApp**, ein SwiftUI-Prototyp (iOS 17, Swift 6, kein Backend, alle Daten
liegen im Speicher über `InMemoryRepository`). Grundidee: täglich einen Song mit der
Gruppe teilen, bewerten, auflösen. Architektur: `AppStore` (zentraler `@Observable`
State) → Repository-Protokolle → `InMemoryRepository`. Views liegen unter
`TodApp/Features/<Bereich>/`, Datenmodelle unter `TodApp/Core/Models/`, Design-Tokens
unter `TodApp/Core/DesignSystem/`.

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

### 2. Gruppen-Ansicht (Instagram-Style)

Neue View (z.B. `Features/Groups/GroupsFeedView.swift`), Instagram-DM-Screen als
Vorbild (siehe Screenshot 1):

- **Oben**: horizontale Story-Leiste mit Kreis-Avataren – zeigt, wer heute schon
  gepostet hat (ähnlich der bestehenden `AvatarBadge`-Logik in `TodayView`, aber als
  eigene Komponente mit echtem Profilbild statt nur Initialen, plus Ring/Hervorhebung
  wenn gepostet wurde). Tippen öffnet direkt den Song dieser Person (siehe Punkt 3).
- **Darunter**: Liste der Tod-Gruppen als Zeilen im Stil einer Chat-Liste (analog zu
  Instagrams Chat-Liste unterhalb der Ordner-Tabs) – pro Zeile: Gruppen-Profilbild,
  Gruppenname, der zuletzt gepostete Song als Vorschau-Text, Uhrzeit rechts (wie ein
  Chat-Preview mit Zeitstempel). Tippen auf eine Zeile öffnet die Song-Detail-Ansicht
  (Punkt 3) für den neuesten Post dieser Gruppe.
- Gruppen brauchen dafür ein **Profilbild-Feld** (aktuell nur `icon: String` als
  Emoji/Symbol) – ergänze echte Bildauswahl/-anzeige (z.B. `imageData`/`imageURL` auf
  `Group`, mit Fallback auf das bestehende `icon`, falls kein Bild gesetzt ist).

### 3. Song-Detail / Kommentar-Ansicht (Screenshot 2)

Beim Antippen eines Posts (aus Story-Leiste oder Gruppenliste) öffnet sich eine
Ansicht mit:

- Player oben in **normaler Größe** (wie der bestehende `TrackPlayerSheet`, nicht
  riesig).
- darunter **groß** der Kommentarbereich: Liste der Kommentare mit Profilbild,
  Autorenname, Zeitstempel, Kommentartext; Eingabefeld unten zum Antworten (ähnlich
  wie das bestehende Chat-Eingabefeld in `ChatView`).
- Dafür reicht `comments: [String]` in `Submission` nicht mehr – ersetze es durch
  eine echte `Comment`-Struktur (id, authorID/-name, Profilbild-Referenz, Text,
  Zeitstempel), inklusive Anpassung in `InMemoryRepository` und überall, wo
  `Submission.comments` bisher gelesen/geschrieben wird.

**Mini-Player-Verhalten (wichtig, siehe Architektur-Hinweis oben):** Wird diese
Ansicht geschlossen, während der Song noch spielt, erscheint unten in der App ein
schmaler, persistenter Mini-Player mit Pause-Taste – **nur solange** ein Song aktiv
spielt (nicht permanent sichtbar). Tippen auf den Mini-Player öffnet wieder die volle
Song-Detail-Ansicht. Das erfordert einen App-weiten Player-Zustand (welcher Song
spielt gerade, sichtbar für Home/Gruppen-Ansicht gleichzeitig), sinnvollerweise in
`AppStore` oder einem eigenen `@Observable`-`PlayerManager`, den `RootTabView` (oder
eine neue Root-Container-View) als `.safeAreaInset(edge: .bottom)` einblendet, analog
zum bestehenden `GroupSwitcher`-Pattern in `RootTabView`.

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

Die App hat aktuell eine Tab-Leiste mit Heute / Voten / Reveal / Rangliste / Chat /
Battle. Wie diese bestehenden Features (Voting, Reveal, Rangliste, Battle) sich in
die neue Struktur mit Home + Gruppen-Ansicht + Profil einfügen, ist **nicht
vorgegeben** – triff hier eine sinnvolle Entscheidung und beschreibe kurz, wofür du
dich entschieden hast (z.B.: weiterhin als Tabs neben Home/Gruppen, oder erreichbar
aus der Gruppen-Detail-Ansicht heraus, oder ein Menü). Wichtig ist nur: keine der
bestehenden Funktionen (Voten, Reveal, Rangliste, Battle, bestehender Gruppenchat)
soll ohne Ersatz verschwinden.

---

## Nicht-Ziele / Out of Scope

- Kein echtes Backend, keine echte Auth – alles bleibt In-Memory wie bisher.
- Keine neue Musik-Quelle – weiterhin nur Spotify/SoundCloud-Embeds über die
  bestehende `TrackSource`/`EmbedURLBuilder`-Logik.
- Profilbilder können vorerst lokale Platzhalter-Assets oder `PhotosPicker`-Auswahl
  sein, kein Upload zu einem Server.

## Nach der Umsetzung

- `xcodegen generate` ausführen (Projekt wird aus `project.yml` erzeugt, nötig nach
  jeder neuen Datei).
- Bestehende Konventionen beibehalten: reine Logik (z.B. Streak-Berechnung) wo
  möglich ohne SwiftUI testen, wie es `TrackSection` und `LeaderboardView.barFraction`
  vormachen.
- `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
  zum Prüfen.
