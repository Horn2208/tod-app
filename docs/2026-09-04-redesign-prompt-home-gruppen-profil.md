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

**Stand:** Der größte Teil dieses Dokuments ist umgesetzt und hier gestrichen –
übrig ist nur noch, was offen ist. Was gebaut ist, wie, und was dabei gemessen
wurde, steht in `docs/UEBERGABE.md`. Die volle Fassung dieses Dokuments liegt in
Git (Commit `8df0654`).

Die zwei angehängten Screenshots zeigen die Instagram-Referenz: Screenshot 1 = obere
Story-Leiste + darunter die Chat-/Ordner-Liste. Screenshot 2 = aufgeklappte Ansicht
mit großem Kommentarbereich, normal großem Player oben, Antwort-Feld unten.

---

## Aufgabe

Offen sind noch die folgenden Punkte. Halte dich an bestehende Architektur
(`AppStore`, Repository-Pattern, Design-Tokens) statt Parallelstrukturen zu bauen.

### 2. Gruppen-Ansicht (Instagram-Style)

Story-Leiste, Gruppenzeilen und Gruppenbilder sind umgesetzt. Offen ist die
Präzisierung zur Story-Leiste:

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

### 3. Gruppen-Chat als Hub

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

**Konsequente Zurückhaltung:** großzügiger Weißraum, pro Screen nur wenige
gleichzeitig sichtbare Akzentfarben, keine bunten Badges nebeneinander. Der
"Premium"-Eindruck kommt eher aus dem sparsamen Einsatz der drei Akzente
(Pink/Gold/Streak-Orange) als aus zusätzlichen Farben.

---

## Monetarisierung – Idee für den ersten Launch

Kein Werbemodell – die App lebt von der engen, privaten Freundesgruppen-Vibe
(täglicher Song, Streak, Voting), das würde durch Ads kaputtgehen. Stattdessen
Freemium, gestaffelt für den Launch:

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
