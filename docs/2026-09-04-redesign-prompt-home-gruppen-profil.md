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

Die Kommentare zu den Bewertungen (nicht die allgemeinen Song-Kommentare) beziehen
sich konkret auf die jeweilige Bewertung – z.B. eine Notiz, warum jemand einen Song
hoch/niedrig bewertet hat. Das ist ein zusätzliches Datenfeld/-konzept gegenüber der
reinen `Comment`-Struktur unten – ergänze es sinnvoll, z.B. optionaler `note`-Text an
`Vote` oder eine eigene Verknüpfung zwischen `RoundScore` und Kommentaren.

Für die allgemeinen Song-Kommentare (nicht die Bewertungs-Notizen) gilt weiter:
`comments: [String]` in `Submission` reicht nicht – ersetze es durch eine echte
`Comment`-Struktur (id, authorID/-name, Profilbild-Referenz, Text, Zeitstempel),
inklusive Anpassung in `InMemoryRepository` und überall, wo `Submission.comments`
bisher gelesen/geschrieben wird.

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

**Mini-Player-Verhalten bleibt wie zuvor beschrieben (wichtig, siehe
Architektur-Hinweis ganz oben):** Egal ob der Song-Swipe-Feed oder ein einzelner Song
im Chat geschlossen wird, während er noch spielt – unten in der App erscheint ein
schmaler, persistenter Mini-Player mit Pause-Taste, **nur solange** ein Song aktiv
spielt (nicht permanent sichtbar). Tippen auf den Mini-Player öffnet die Stelle
wieder, an der der Song lief. Dafür weiterhin ein App-weiter Player-Zustand
(`AppStore` oder eigener `@Observable`-`PlayerManager`), eingeblendet über
`.safeAreaInset(edge: .bottom)` analog zum bestehenden `GroupSwitcher`-Pattern in
`RootTabView` – die WebView darf dabei wie schon beschrieben nicht neu erzeugt
werden, sonst stoppt die Wiedergabe.

**Entscheidung: komplett eigener Mini-Player statt Spotifys/Apples fertiger
Embed-UI, für alle Nutzer:innen einheitlich, egal ob Premium/Abo oder nicht.**

**Spotify – über die iFrame API (`EmbedController`), nicht das Web Playback SDK.**
Aktuell zeigt `TrackEmbedView` Spotifys fertiges Embed-Widget mit dessen eigenem
Aussehen. Statt des schwereren Web Playback SDK (das einen vollen OAuth-Access-Token
mit `streaming`-Scope pro Wiedergabe braucht) reicht die leichtere
[iFrame API](https://developer.spotify.com/documentation/embeds/references/iframe-api):
sie läuft im selben, schon vorhandenen `WKWebView`-Embed, stellt aber einen
`EmbedController` mit echten Steuerbefehlen bereit – `play()`, `pause()`,
`resume()`, `togglePlay()`, `seek(sekunden)`, `restart()` – plus Events wie
`playback_update` (liefert `position`, `duration`, `isPaused`, `isBuffering`). Die
WebView wird dabei komplett unsichtbar/größe 0 gemacht, und der komplette
Mini-Player (Progressbar, Play/Pause-Button) wird in SwiftUI mit den eigenen
`todAccent`-Farben/Gradients aus dem "Modern Premium"-Abschnitt gebaut – für
**alle** Nutzer:innen dieselbe eigene Optik, nicht nur für Premium.

Ob dabei 30 Sekunden oder der volle Song laufen, entscheidet Spotify serverseitig
anhand des Login-Zustands der WebView, nicht die App: **ohne** eingeloggten
Spotify-Account läuft automatisch die 30-Sekunden-Vorschau (kein Login nötig), **mit**
einmalig eingeloggtem Premium-Account (normale Spotify-Login-Seite, einmal in einer
WebView geöffnet, Session bleibt über `WKWebsiteDataStore` dauerhaft gespeichert)
läuft der volle Song – **ohne dass sich das Login-Fenster vor jedem Songstart
erneut öffnet**. Das ist einfacher umzusetzen als der volle Web-Playback-SDK-Weg mit
manuellem Access-Token/Refresh-Handling, weil die iFrame API mit dem
Browser-Session-Zustand arbeitet statt mit einem selbst verwalteten OAuth-Token.
(Das Web Playback SDK bleibt eine Alternative, falls später tiefere
Spotify-Connect-Steuerung gebraucht wird – für den Mini-Player reicht die iFrame API.)

Für SoundCloud gibt es kein Äquivalent zur iFrame API – dafür bleibt vorerst der
bestehende Embed-Weg (`TrackEmbedView`/`EmbedURLBuilder`) mit Spotifys/SoundClouds
eigenem Widget-Look, bis entschieden wird, ob SoundCloud als Quelle überhaupt
erhalten bleibt oder ob sich der Aufwand für eine eigene SoundCloud-Optik lohnt.

**Apple Music – nativ über `MusicKit`, ganz ohne WebView.** Sobald der bezahlte
Apple Developer Account läuft (siehe oben), lässt sich Apple Music sogar einfacher
komplett eigen gestalten als Spotify: das native Swift-Framework `MusicKit`
(`ApplicationMusicPlayer`, seit iOS 15) steuert Wiedergabe direkt in Swift –
`play()`/`pause()` aufrufen, Fortschritt/Status über normale Swift-Properties
beobachten – ganz ohne JavaScript-Brücke oder versteckte WebView. Die eigene
SwiftUI-Player-UI baut sich dabei so natürlich wie jede andere Ansicht in der App.
Login läuft über die native System-Berechtigung (`MusicAuthorization.request()`,
ein normaler iOS-Berechtigungsdialog "Medien & Apple Music", kein Web-Login) – für
den vollen Song braucht die Person weiterhin ein aktives Apple-Music-Abo, für die
Vorschau ohne Abo gibt es im Apple-Music-Katalog ein `previews`-Feld mit einem
kurzen Ausschnitt (als Fallback zusätzlich die alte, offene iTunes-Search-API, seit
Jahren stabil, ganz ohne Entwickler-Account nutzbar).

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

- Kein echtes Backend, kein eigenes Login-System für TodApp selbst – alles bleibt
  In-Memory wie bisher. **Ausnahme:** der einmalige Spotify-Login (für die volle
  Wiedergabe über die iFrame API) und die native Apple-Music-Berechtigung sind
  echte, notwendige Logins gegenüber Spotify bzw. Apple – das ist kein App-eigenes
  Backend, sondern läuft komplett gegen deren eigene Login-/Berechtigungs-Systeme.
- Keine neue Musik-**Quelle** – weiterhin Spotify und SoundCloud (plus optional
  Apple Music, sobald der bezahlte Developer-Account läuft) über die bestehende
  `TrackSource`-Logik. Die Art der Einbindung ändert sich für Spotify wie oben
  beschrieben von reinem Embed-Widget zu eigenem Mini-Player über die iFrame API;
  SoundCloud bleibt vorerst beim Embed-Widget-Look.
- **Kein Premium-Zwang:** Spotify Premium bzw. ein Apple-Music-Abo ist **nicht**
  Voraussetzung, um die App zu nutzen – ohne Abo läuft automatisch die
  30-Sekunden-Vorschau im selben, eigenen Player, mit Abo der volle Song. Posten und
  Song-Abschnitt auswählen funktioniert so oder so.
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
