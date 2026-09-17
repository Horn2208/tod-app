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

### 3. Gruppen-Chat als Hub

**g) Musik-Architektur (Kursänderung, erst teilweise umgesetzt): Apple Music
soll die primäre Quelle für Suche, Posten und Wiedergabe werden; Spotify nur
noch als optionaler Such-/Link-Import.** Der Teil ohne bezahlten Account läuft
bereits: ein über Spotify gepostetes Lied spielt automatisch Apples
30-Sekunden-Vorschau nativ (`AVPlayer`/`PreviewPlayer`), sobald die offene
iTunes-Search-API dieselbe Aufnahme findet (Titel + Hauptkünstler + Länge auf
3 s genau, siehe `CatalogMatch`/`CatalogResolver`) – ohne WebView, ohne Login.
Ohne Treffer spielt weiterhin Spotifys eigenes Embed. **Korrektur:** Apples
Vorschau ist gemessen **30 Sekunden** lang (vier Songs zwischen 200–354 s
geprüft, immer exakt 30,0 s), nicht "ca. 90 Sekunden" wie hier früher stand.

**Noch offen, bevor MusicKit als Hauptweg gebaut wird – drei konkrete
Blocker:**
1. **Client-Credentials-Flow braucht ein Client-Secret** (App-Token, kein
   Nutzer-Login) – genau das hat das Projekt bewusst abgeschafft (PKCE, kein
   Proxy mehr, das alte Secret ist im Spotify-Dashboard zu widerrufen). Vor
   dem Umbau klären, ob/wie ein Secret sicher zurückkommt (z.B. hinter einer
   kleinen Supabase Edge Function statt direkt in der App, siehe Abschnitt 7).
2. **Der bezahlte Apple-Developer-Account ist jetzt da** – der Developer-Token
   für die Apple-Music-API (Endpoint "Get Multiple Catalog Songs by ISRC")
   lässt sich damit ziehen. Die offene iTunes-API kann weiterhin keinen
   ISRC-Abgleich (`lookup` kennt laut Apples Doku keinen `isrc`-Parameter,
   getestet: null Treffer) – der echte ISRC-Abgleich läuft über die bezahlte
   Apple-Music-API. Noch zu tun, bevor das gebaut wird: MusicKit-Capability für
   `com.lennetschierhorn.TodApp` auf developer.apple.com aktivieren und die
   Team-ID in `project.yml` eintragen (siehe `docs/UEBERGABE.md`, „Was der
   Nutzer selbst tun muss“).
3. **Ungetestet:** die Annahme, volle Song-Wiedergabe über Spotifys Embed gehe
   nur im Desktop-Browser, nie in einer nativen App. Test dafür: im Profil bei
   Spotify anmelden (Premium), einen langen Song öffnen, prüfen ob die
   `embed`-Spur die volle Länge zeigt statt der 30s-Vorschau.

Bis Punkt 1 geklärt ist, bleibt Spotify-Suche über den bestehenden
OAuth/PKCE-Login (nicht Client-Credentials). Der native `MusicKit`/
`ApplicationMusicPlayer`-Pfad fürs ganze Lied ist als Weiche vorbereitet
(`TrackPlayerSheet.player(for:catalog:spotifyWebSession:appleMusicWholeSongs:)`),
aber eine echte MusicKit-Anfrage ist noch ungeprüft – mit dem Account jetzt
aber machbar, sobald MusicKit-Capability + Team-ID gesetzt sind (Punkt 2).
Deezer (Nutzungsbedingungen verbieten kommerzielle Nutzung) und die
YouTube-iFrame-API (verbietet, etwas über den Player zu legen) bleiben wie
entschieden unverwendet.

**h) Quellen-Icons auf dem Mini-Player.** Grundmechanik ist gebaut
(`SourceAttribution.swift`): Apple-Music-Icon immer sichtbar, zusätzlich ein
Spotify-Icon, wenn der Song ursprünglich über einen Spotify-Link/-Suche
gefunden wurde. **Noch offen:** die Icons sind aktuell SF-Symbol-Platzhalter,
keine echten Marken-Logos – vor einem echten Launch durch die offiziellen
Marken-Assets von Apple ("Apple Music Identity Guidelines") bzw. Spotify
("Spotify Design"-Richtlinien) ersetzen, beide Anbieter haben feste Vorgaben,
wie ihr Logo neben fremden Inhalten dargestellt werden darf/muss.

**i) UX: Free/Premium-Unterschied beim gewählten Abschnitt sichtbar machen
(neu).** Die zugrundeliegende Logik gibt es schon – `SectionStart.decide()`
entscheidet zur Laufzeit anhand von Position/Länge, ob das, was gerade läuft,
den gewählten Startpunkt überhaupt enthält, und `TrackPlayerSheet.player(for:
catalog:spotifyWebSession:appleMusicWholeSongs:)` wählt je Hörer:in zwischen
`.appleMusic` (ganzer Song, startet exakt am gewählten Punkt), `.own`
(Spotify-Embed mit Premium-Session, ebenfalls ab dem Punkt) und
`.applePreview`/`.embed` (feste 30s-Plattform-Vorschau, Startpunkt wird
ignoriert). Zwei Stellen kommunizieren das noch nicht gut genug:

- **Ersteller-Screen (`TrackSectionPicker`).** Aktuell nur der neutrale Hinweis
  "Ziehe den Clip zu deinem Lieblingsbereich." – nirgends steht, dass der
  gewählte Punkt nur mit Premium/Abo bei Spotify oder Apple Music exakt so
  ankommt, alle anderen hören die feste Standard-Vorschau der Plattform (meist
  Anfang oder Refrain, nicht der gewählte Punkt). Neu: ein ruhiger,
  permanenter Zusatzsatz unter der Start/Länge/Ende-Zeile, im Ton der übrigen
  Hinweise (`todTextDim`/`todTextFaint`, kein Rot/Orange, keine Alarm-Optik,
  siehe "Konsequente Zurückhaltung" oben) – etwa: "Diesen Punkt hören andere
  nur mit Premium bei Spotify oder Apple Music. Ohne Abo läuft die kurze
  Standard-Vorschau der Plattform." Statisch, nicht bei jedem Ziehen neu
  eingeblendet.
- **Hörer-Screen, Feed-Karte (`QuickPlayButton`, bereits gebaut).** Der
  Play-Button auf der Song-Karte im Feed sieht für `.wholeSong`, `.preview`
  und `.embed` aktuell identisch aus – kein Signal, ob gleich der exakte, vom
  Poster gewählte Abschnitt oder nur die generische Plattform-Vorschau läuft.
  Das volle `TrackPlayerSheet` erklärt die Lage bereits gut in Textform (siehe
  `SpotifyOwnPlayer`/`ApplePreviewPlayer`, z.B. "Spotify liefert hier nur die
  30-Sekunden-Vorschau … Ganze Songs gibt es mit Spotify Premium …"), aber nur
  im Sheet, nicht auf der kompakten Karte. Neu: ein kleines, dezentes Indiz
  direkt am `QuickPlayButton` – ein einzelnes, unaufdringliches Zeichen (kein
  Warndreieck, keine Ampelfarbe – eher ein kleiner Zeitstempel/Uhr-Punkt in
  `todTextFaint` am Rand des Buttons), nur bei `.preview`/`.embed`
  eingeblendet, nie bei `.wholeSong`. So wirkt die kürzere/andere Vorschau wie
  eine bewusste Eigenschaft des Dienstes statt wie ein Fehler – wer mehr
  wissen will, tippt aufs Cover und landet im Sheet mit der ausführlichen
  Erklärung, die es schon gibt.

**Kurz skizzierter Playback-Flow (bereits so gebaut, hier nur zusammengefasst):**
1. Beim Posten wird nur die Track-Referenz (ISRC/Apple-Music-ID/Spotify-Quelle)
   plus der gewählte `TrackSection.start` gespeichert – ein Wert, gleich für
   alle Hörer:innen, keine Kopie pro Person.
2. Beim Öffnen/Abspielen entscheidet **pro Hörer:in** `TrackPlayerSheet.player(
   for:catalog:spotifyWebSession:appleMusicWholeSongs:)`:
   - Katalog-Match **und** `appleMusic.playsWholeSongs` (aktive MusicKit-
     Berechtigung + Abo) → `.appleMusic`: `AppleWholeSongPlayer` lädt den Song
     und startet direkt bei `section.start` – exakt der gewählte Punkt, kein
     Raten nötig.
   - Sonst, mit Spotify-Premium-Session im Profil (`spotifyWebSession == true`)
     → `.own`: Spotifys Embed lädt ebenfalls ab `section.start`.
   - Sonst → `.applePreview`/`.embed`: feste 30s-Vorschau der Plattform,
     `section.start` wird ignoriert.
3. `SectionStart.decide(start:position:duration:)` ist die eigentliche
   Laufzeit-Prüfung bei `.own`: `duration <= excerptLength` (~30,5s) oder
   `start` jenseits des Endes → `outsideWhatPlays` (das ist die Vorschau, der
   gewählte Punkt fehlt, Hinweistext erscheint); sonst `inPlace`/`seek(to:)` je
   nachdem, ob schon am richtigen Punkt gestartet wurde.

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

Für den bereits gebauten Erinnerungs-Broadcast (Premium-Feature im "+"-Sheet,
bisher simulierter/In-App-Versand statt echtem Push) wäre mit dem Server jetzt
auch ein echter Push über eine Supabase Edge Function + APNs möglich – das ist aber ein größerer Zusatzaufwand
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
für die eingebettete Song-Karte bei Song-Erwähnungen im Chat – ein durchgängiges
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

- **Erinnerungs-Broadcast an die ganze Gruppe ist ebenfalls Premium** (bereits
  gebaut) – die Aktion im "+"-Sheet neben Battle, mit der man allen
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
  Suche/Import perspektivisch keinen Nutzer-Login (Client-Credentials-Flow,
  siehe 3g – aktuell aber noch über den bestehenden OAuth/PKCE-Login, bis die
  drei Blocker in 3g geklärt sind).
- **Musik-Quelle, Kursänderung erst teilweise umgesetzt (siehe 3g):** Apple
  Music **soll** die primäre Wiedergabe-Quelle werden (über `MusicKit`). Der
  bezahlte Apple-Developer-Account ist jetzt da – noch zu tun: MusicKit-
  Capability aktivieren + Team-ID in `project.yml`. Bisher läuft automatisch
  nur Apples 30-Sekunden-Vorschau über die offene iTunes-Suche, ohne Login.
  Spotify bleibt als Such-/Link-Quelle erhalten; ISRC-Matching auf den
  passenden Apple-Music-Track ist mit dem Account jetzt machbar, siehe 3g.
  SoundCloud und der bisherige `TrackEmbedView`-Embed-Weg bleiben als
  Fallback. Deezer und die YouTube-iFrame-API wurden geprüft und bewusst
  nicht verwendet (siehe 3g – Nutzungsbedingungen bzw. Design-Konflikt).
- **Kein Abo-Zwang:** Ein Apple-Music-Abo ist **nicht** Voraussetzung, um die App
  zu nutzen – ohne Abo läuft automatisch die Apple-Music-Vorschau (bzw. iTunes-
  Search-API als Fallback) im selben, eigenen Player, mit Abo der volle Song.
  Posten und Song-Abschnitt auswählen (bereits umgesetzt, `TrackSectionPicker`/
  `SectionStart`) funktioniert für alle gleich – nur ob der gewählte Abschnitt
  beim Voten auch tatsächlich hörbar ist, hängt vom Abo-Status der jeweiligen
  Person ab, nicht das Wählen selbst.
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

---

## Fahrplan bis TestFlight / App Store (neu, 17. September)

Vier Phasen, jede baut auf der vorigen auf. Reihenfolge ist bewusst so gewählt,
weil Phase 1 der größte technische Brocken ist und alles danach davon abhängt,
dass Daten überhaupt über einen Neustart hinweg bestehen bleiben.

**Phase 1 – Backend & Persistenz (größter Brocken).** Der Supabase-Server
existiert bereits (Account eingerichtet) – offen ist die Code-Seite, die
genauso viel Arbeit bleibt wie in Abschnitt 7 beschrieben: `SupabaseRepository`
bauen (erfüllt dasselbe Protokoll wie `InMemoryRepository`), Tabellen-Schema
anlegen, RLS-Policies pro Tabelle aktivieren, Supabase Auth (Sign in with
Apple/Magic-Link) statt des `currentUserID = "du"`-Stubs, Storage-Bucket für
Profil-/Gruppenbilder. Ohne diese Phase verliert jeder App-Neustart alle
Gruppen/Posts/Streaks – für eine echte Freundesgruppe (auch nur zum Testen)
nicht nutzbar.

**Phase 2 – Musik-Feature-Reste.** MusicKit-Capability aktivieren + Team-ID in
`project.yml` eintragen (Account ist da, siehe 3g Punkt 2); den bereits
gebauten Premium-Spotify-Test selbst verifizieren (3g Punkt 3); Quellen-Icons
gegen echte Apple-/Spotify-Marken-Assets tauschen (3h); die Free/Premium-UX-
Hinweise aus Punkt 3i bauen.

**Phase 3 – TestFlight-Vorbereitung.** Gerätetests sind teilweise schon
passiert (auf deinem iPhone getestet) – zusätzlich noch die spezifischen
Musik-/Premium-Tests aus `docs/UEBERGABE.md` einmal gezielt durchgehen. Dazu:
ein **App-Icon erstellen** (aktuell existiert im Projekt kein einziges
`Assets.xcassets` – das fehlt komplett), einen App-Store-Connect-Eintrag mit
Bundle-ID anlegen, einen Build hochladen, interne Tester (die Freundesgruppe)
einladen. Für rein interne TestFlight-Tester sind Privacy-Manifest,
Datenschutzerklärung und echte In-App-Käufe noch nicht zwingend nötig.

**Phase 4 – App-Store-Reife.** Erst nach TestFlight-Feedback: **Privacy-
Manifest** (`PrivacyInfo.xcprivacy`, seit 2024 von Apple für viele APIs
Pflicht, existiert im Projekt noch nicht), **Datenschutzerklärung** (Pflicht
wegen Login/Supabase Auth), **echte StoreKit-Anbindung** fürs Premium-Abo
(`UserProfile.isPremium` ist aktuell nur eine lokale Bool, laut Code-Kommentar
"not wired to StoreKit yet" – Battle und der Erinnerungs-Broadcast hängen
daran), App-Store-Connect-Metadaten (Beschreibung, Screenshots, Kategorie,
Preis), Einreichen zur Apple-Review (üblicherweise 1–3 Tage, bei Erstanträgen
gelegentlich länger).
