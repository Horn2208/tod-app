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
   `com.lennetschierhorn.TodApp` auf developer.apple.com aktivieren (siehe
   `docs/UEBERGABE.md`, „Was der Nutzer selbst tun muss“). Die Team-ID steht
   schon in `project.yml` (`DEVELOPMENT_TEAM`).
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

**Phase 2 – Musik-Feature-Reste.** MusicKit-Capability aktivieren (Account ist
da, Team-ID steht in `project.yml`, siehe 3g Punkt 2); den bereits gebauten
Premium-Spotify-Test selbst verifizieren (3g Punkt 3); Quellen-Icons gegen
echte Apple-/Spotify-Marken-Assets tauschen (3h). Die Free/Premium-Hinweise
(früher Punkt 3i) sind gebaut.

**Phase 3 – TestFlight-Vorbereitung.** Gerätetests sind teilweise schon
passiert (auf deinem iPhone getestet) – zusätzlich noch die spezifischen
Musik-/Premium-Tests aus `docs/UEBERGABE.md` einmal gezielt durchgehen. Dazu:
ein **App-Icon erstellen** (aktuell existiert im Projekt kein einziges
`Assets.xcassets` – das fehlt komplett), einen App-Store-Connect-Eintrag mit
Bundle-ID anlegen, einen Build hochladen, interne Tester (die Freundesgruppe)
einladen. Für rein interne TestFlight-Tester sind Privacy-Manifest,
Datenschutzerklärung und echte In-App-Käufe noch nicht zwingend nötig.

**✅ Status (25. September):** Das App-Icon existiert bereits (`TodApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png`) — dieser Punkt aus Phase 3 ist nicht mehr offen.

**Phase 4 – App-Store-Reife.** Erst nach TestFlight-Feedback: **Privacy-
Manifest** (`PrivacyInfo.xcprivacy`, seit 2024 von Apple für viele APIs
Pflicht, existiert im Projekt noch nicht), **Datenschutzerklärung** (Pflicht
wegen Login/Supabase Auth), **echte StoreKit-Anbindung** fürs Premium-Abo
(`UserProfile.isPremium` ist aktuell nur eine lokale Bool, laut Code-Kommentar
"not wired to StoreKit yet" – Battle und der Erinnerungs-Broadcast hängen
daran), App-Store-Connect-Metadaten (Beschreibung, Screenshots, Kategorie,
Preis), Einreichen zur Apple-Review (üblicherweise 1–3 Tage, bei Erstanträgen
gelegentlich länger).

**✅ Status (25. September):** `PrivacyInfo.xcprivacy` existiert bereits im Projekt — dieser Teil von Phase 4 ist nicht mehr offen. Datenschutzerklärung und die echte StoreKit-Anbindung sind weiterhin offen.

---

## Layout-Konzept: Player- und Bewertungs-Ansicht (neu, 17. September)

Feingeschliffenes Layout für zwei bestehende Screens, Usability-Fokus (Touch-Targets,
visuelle Hierarchie). Bestehende Farb-/Material-Tokens weiterverwenden, keine neuen
erfinden.

### Waveform- & Player-Ansicht (`TrackPlayerSheet`)

**Größtenteils ✅ erledigt (Stand 25. September):** Cover, Waveform mit Farbverlauf, Zeitangabe, Play-Button und Plattform-Pills sind in `TrackPlayerSheet.swift` umgesetzt. **Noch offen:** Punkt 1 (Cover als ~70%-Hero — aktuell fix 260×260pt statt relativ zur Bildschirmbreite), Punkt 2 (Marquee-Truncation für lange Titel, nicht vorhanden), Punkt 3 (Info-Icon mit Popover für den technischen Hinweistext — aktuell steht der volle Erklärsatz direkt im Screen, z. B. in `SpotifyOwnPlayer`).

Von oben nach unten:

1. **Albumcover als Hero-Element**, nicht als kleines Thumbnail: groß (~70% der
   Bildschirmbreite), zentriert, abgerundete Ecken, leichter Schatten. Dahinter der
   Cover-Art-Glow aus dem Home-Screen (dominante Cover-Farbe, `.blur(radius: 60)`) –
   macht den Player-Screen konsistent mit Home statt wie ein eigener Stil.
2. **Songtitel + Künstler** direkt darunter (`.todDisplay()` / `.todTextDim`), mit
   Marquee-Truncation bei langen Titeln statt Zeilenumbruch.
3. **Technischer Hinweistext hinter einem Info-Icon**: (i)-Button neben Titel/Künstler
   öffnet den vollen Erklärtext als Popover. Im Screen selbst nur eine komprimierte
   Zeile in `todTextFaint`/`todMono()` (z.B. „Vorschau · 30s“) statt drei Zeilen
   API-Erklärung. Begründung: Erstnutzer brauchen die Erklärung einmal, danach ist
   sie Rauschen – ein Icon bedient beide Gruppen ohne dauerhaften Platzverlust.
4. **Waveform**: dünnere Balken, abgespielter Teil in `todAccent`-Gradient, Rest
   gedimmt/`todSurface2`. Scrubbing per Drag bleibt, zusätzlich Haptic Feedback an
   den 5-Sekunden-Schritten (Parität zur VoiceOver-Wischgeste).
5. **Play-Button + Zeit**: großer runder Button in Akzentfarbe mit Fortschrittsring
   (Mini-Player-Muster, eine Stufe größer), Zeitangabe darunter zentriert statt
   seitlich.
6. **Plattform-Buttons statt Text-Links**: zwei Pill-Buttons mit Icon + Label
   („▶ Apple Music“ / „▶ Spotify“), `.ultraThinMaterial`-Hintergrund, mind. 44×44pt
   Touch-Target, ≥12pt Abstand dazwischen.

UX-Begründung: Cover schafft emotionalen Anker (Now-Playing-Pattern von Apple
Music/Spotify), Info-Icon trennt Pflicht- von Zusatzinfo, Buttons statt Links
erhöhen die Tap-Erfolgsrate (Fitts’s Law – Fläche schlägt Textzeile).

### Bewertungs-Ansicht (Rating-Feed)

**✅ Erledigt (Stand 25. September):** Alle drei Punkte sind in `SongFeedView.swift` bereits genau so umgesetzt — größeres Segment (44pt-Felder, skaliert beim Antippen), Hidden-Gem als goldener Toggle-Pill, und Bewertungsleiste + Gem-Toggle + Kommentarfeld in einer gemeinsamen `.ultraThinMaterial`-Karte. Nichts mehr offen hier.

1. **Bewertungs-Chips vergrößern**: fünf Chips nebeneinander auf iPhone-Breite
   unterschreiten oft das 44pt-Mindestmaß. Statt Slider (ungenauer bei benannten
   diskreten Stufen) ein horizontales Segment mit größeren, gleich breiten Feldern,
   das beim Antippen sichtbar skaliert und die gewählte Bewertung per Hintergrundfüllung
   hervorhebt (nicht nur Textfarbe).
2. **„Hidden Gem“ als eigenständiger Toggle-Button statt Text mit Icon**: Pill mit
   Edelstein-Symbol, füllt sich beim Aktivieren (Gold-Gradient wie schon bei „💎 3
   Hidden Gems“ verwendet), leichte Skalier-Animation beim Antippen. Direkt unter der
   Bewertungsleiste platziert (Nähe = Zusammengehörigkeit), nicht isoliert darunter.
3. **Kommentarfeld optisch in denselben Block einfassen**: Bewertungsleiste, Hidden-
   Gem-Toggle und Kommentarfeld in eine gemeinsame Karte (`.ultraThinMaterial` +
   `todLine`-Rand) statt drei getrennte Elemente. Feld öffnet beim Antippen wie beim
   bestehenden `NoteComposer` eine Eingabeleiste über der Tastatur statt mitten im
   Screen zu stehen.

UX-Begründung: größere, klar abgegrenzte Tap-Ziele senken Fehltipps beim schnellen
Durchwischen; ein greifbarer Toggle macht „Hidden Gem“ auffindbar statt es hinter
einer Textzeile zu verstecken; eine gemeinsame Karte gibt dem Auge einen Bewertungs-
block statt drei fragmentierter Aktionen.

### Mini-Player-Anordnung in der Tab-Leiste (neu, 17. September)

**✅ Erledigt (24./25. September):** Umgesetzt in `TodApp/Features/Player/RootNavBar.swift` (neu) sowie Anpassungen in `RootTabView.swift` und `MiniPlayerRoom.swift`. Ohne Musik sitzen Home und Gruppen zusammen in einer Glas-Kapsel wie die alte Tab-Leiste; läuft ein Song, rücken sie als runde Glasknöpfe auseinander und die Mini-Player-Pille erscheint dazwischen, alle drei auf einer Höhe. Ab iOS 26 echtes Liquid Glass (fließt beim Auseinander- und Zusammengehen). Die System-Tab-Leiste ist ganz ersetzt. Wischen über die Leiste wechselt zwischen Home und Gruppen; eine Wischgeste über den ganzen Bildschirm gibt es bewusst nicht (würde sich mit dem Bewertungs-Feed beißen). Nichts mehr offen hier.

Referenzbild vom Nutzer (Screenshot einer anderen App, Layout übernehmen): Der
Mini-Player sitzt als schwebende Glas-Pille **zwischen** den beiden äußeren
Tab-Buttons, nicht darüber oder als eigene Zeile. Konkrete Anordnung von links
nach rechts:

- **Home-Button ganz links** (eigener runder Button, kein Bestandteil der Pille).
- **Mini-Player-Pille in der Mitte**, breiter als die beiden Buttons, mit Cover,
  Titel/Künstler und Play-/Pause-Button darin (wie bereits weiter oben in diesem
  Dokument beschrieben).
- **Gruppen-Button ganz rechts** (eigener runder Button).

Alle drei Elemente auf gleicher Höhe, mit sichtbarem Abstand zueinander (kein
Verschmelzen zu einer durchgehenden Leiste) — die Pille bleibt optisch das
größte/wichtigste Element in der Mitte, die beiden Navigations-Buttons links und
rechts davon kleiner und rund, passend zum bestehenden „Glas statt Fläche“-Look.

### Player-Vollansicht: neues Referenzdesign (neu, 18. September)

**Größtenteils ✅ erledigt (Stand 25. September):** In `TrackPlayerSheet.swift`/`SongDetailView.swift` bereits umgesetzt: Cover, Titel/Künstler, Waveform mit zentrierter Zeit, Drei-Buttons-Reihe (15s zurück – großer Play-Button – 15s vor), Lautstärke-Slider mit Lautsprecher-Icons, zwei Plattform-Pills, und Kommentare direkt im selben Screen (Avatar, Name, Zeit, Text, Eingabefeld über der Tastatur). Die dynamische Verlaufsfarbe pro Song (statt fixem Pink) ist ebenfalls schon so, wie hier gefordert. **Noch offen:** Cover-Größe ist fix 260×260pt statt relativ zur Bildschirmbreite (~70%).

Referenzbild vom Nutzer (Screenshot, Layout 1:1 übernehmen). Von oben nach unten:

1. **Cover groß und zentriert** oben im Screen, abgerundete Ecken, dezenter Schatten.
2. **Titel** fett direkt darunter, **Künstler** eine Zeile darunter, gedimmt.
3. **Waveform mit Farbverlauf** statt einfarbig — der bereits gespielte Teil zieht
   sichtbar heller/kräftiger als der Rest, keine harte Kante.
4. **Zeitangabe** darunter zentriert („0:24 / 2:01“).
5. **Drei Steuerungs-Buttons in einer Reihe**: Zurück (15s/vorheriger Abschnitt) –
   Play/Pause groß und in Akzentfarbe gefüllt, deutlich größer als die beiden
   Nachbar-Buttons – Vor. Zurück/Vor kleiner und neutral (grau), damit der Play-
   Knopf klar der wichtigste ist.
6. **Lautstärke-Slider** darunter, volle Breite, mit kleinen Lautsprecher-Icons an
   beiden Enden.
7. **Zwei Plattform-Pills nebeneinander**: „Music öffnen“ / „Spotify öffnen“, je
   mit kleinem Marken-Icon links im Button, abgerundete Kapselform, dezente
   Umrandung statt Vollfläche.
8. **Kommentare direkt im selben Screen** statt in eigenem Sheet: Überschrift
   „N Kommentare“, darunter die Liste (Avatar, Name, Zeit, Text), ganz unten ein
   Eingabefeld mit Senden-Button, das über der Tastatur sitzt.

**Wichtig, Abweichung vom Referenzbild:** Die Verlaufsfarbe im Hintergrund (im
Screenshot sattes Pink/Magenta) ist dort exemplarisch und **nicht** fest zu
übernehmen. Sie bleibt dynamisch aus dem Cover abgeleitet
(`ArtworkColor`/Cover-Art-Glow, siehe oben in diesem Dokument) — jeder Song
bekommt weiterhin seine eigene Verlaufsfarbe statt eines einheitlichen Pink-Looks.
Struktur, Anordnung und Formensprache (Pills, abgerundete Kapseln, Play-Button-
Betonung) folgen dem Referenzbild, die Farbe folgt dem bestehenden System.

## Umgesetzt (24. September)

- **Mini-Player in der Tab-Leiste**: `RootNavBar.swift` neu, `RootTabView.swift` und `MiniPlayerRoom.swift` angepasst – Home-Button links, Mini-Player als Glas-Pille in der Mitte, Gruppen-Button rechts, alle auf einer Höhe. Die System-Tab-Bar ist ausgeblendet, `RootNavBar` ersetzt sie.
- **Wischen zwischen Home und Gruppen**: zusätzlich zum Tippen auf `RootNavBar` kann man jetzt horizontal wischen, um die Seite zu wechseln – wischen nach links geht von Home zu Gruppen, wischen nach rechts zurück zu Home (passend zur Reihenfolge Home links / Gruppen rechts). Umgesetzt in `RootTabView.swift` über eine `DragGesture` auf dem `TabView` mit `selection`-Bindung; eine Schwelle (horizontale größer als vertikale Bewegung) hält das aus dem Weg von vertikalem Scrollen und vom horizontalen Gruppen-Icon-Streifen oben in `GroupsFeedView`.

## Code-Audit (24. September)

Code gegen den Stand dieses Dokuments geprüft – Player-Vollansicht, Bewertungs-Screen, Fahrplan-Punkte. Für den anderen Code-Agenten aufbereitet, keine Änderungen selbst vorgenommen. (Die Ergebnisse sind jetzt zusätzlich direkt bei den betroffenen Abschnitten oben als Status-Hinweise vermerkt.)

**Doc war an drei Stellen veraltet – bereits erledigt, obwohl oben ursprünglich noch als offen beschrieben:**
- App-Icon existiert bereits (`TodApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).
- `PrivacyInfo.xcprivacy` existiert bereits im Projekt.
- Die Player-Vollansicht nach dem Dolce-Referenzdesign ist in `TrackPlayerSheet.swift` und `SongDetailView.swift` schon fast vollständig umgesetzt.
- Bewertungs-Screen: Leerzustände sind bereits vorhanden ("Heute noch nichts zu bewerten" / "Noch nichts aufgedeckt" in `SongFeedView.swift`, sowie "Niemand hat bewertet." beim Reveal ohne Stimmen).

**Tatsächlich noch offen, für den Code-Agenten:**
1. Info-Icon/Popover für den technischen Hinweistext fehlt (`TrackPlayerSheet.swift`, z. B. `SpotifyOwnPlayer`).
2. Marquee-Truncation für lange Songtitel fehlt.
3. Cover-Größe in der Player-Vollansicht ist fix (260×260pt), nicht relativ zur Bildschirmbreite wie im Referenzdesign (~70%).

Nicht geprüft (Zeit/Aufwand): Chat, Leaderboard, Profil, Battle, PostSong-Flow im Detail – bei Bedarf gezielt nachreichen.

## Wichtig, jetzt umsetzen: SoundCloud mit versteckendem Player (25. September)

**Ziel:** SoundCloud soll genau wie Spotify über einen unsichtbaren Embed laufen, gesteuert von den App-eigenen Bedienelementen (Waveform, großer Play-Button, 15s-Skip, Zeit) statt über SoundClouds eigenes sichtbares Widget.

**Ist-Zustand (geprüft, Stand 25. September):** `TrackPlayerSheet.swift` zeigt für SoundCloud (`case .widget`, Funktion `soundCloudWidget(_:)`) aktuell `TrackEmbedView` – ein `WKWebView`, das SoundClouds offizielles `w.soundcloud.com/player`-iFrame lädt und **sichtbar** anzeigt (eigene SoundCloud-Bedienelemente, `visual=false` blendet nur das Cover-Bild aus, nicht den Player selbst). Dazu der Hinweis "Der Abschnitt ist gesetzt. Das SoundCloud-Widget spielt den Song trotzdem von Anfang an.", weil das SoundCloud-Widget nicht steuerbar ist.

**Vorbild, 1:1 im Projekt vorhanden:** Spotify läuft schon genau so, wie SoundCloud es jetzt auch tun soll. Vorlage:
- `TodApp/Core/Music/Embed/SpotifyEmbedPlayer.swift` (395 Zeilen): eine `@Observable`-Klasse mit einer `WKWebView` bei Größe 0 (`frame: .zero`, `isUserInteractionEnabled = false`), die eine lokale HTML-Seite lädt (Spotifys iFrame-API), über einen `WKScriptMessageHandler`-Bridge (`Bridge`, `WKScriptMessageHandler`) Play/Pause/Progress-Events zurückmeldet, und Befehle per `webView.evaluateJavaScript("window.<function>(...)")` an die Seite schickt. Zustand: `status`, `isPaused`, `position`, `duration`, `embedError`. Befehle: `load(_:startAt:)`, `play()`, `pause()`.
- `TodApp/Features/Player/TrackPlayerSheet.swift`, `private struct SpotifyOwnPlayer` (um Zeile 513): die SwiftUI-Ansicht, die den `SpotifyEmbedPlayer` liest und die App-eigene `Transport`-Komponente (Waveform, Play-Button, Zeit, 15s-Skip) darauf zeichnet – der Nutzer sieht nur TodApp-UI, nie Spotifys Widget.
- Registriert als eine einzige App-weite Instanz in `TodApp/App/TodApp.swift` Zeile 33 (`@State private var embedPlayer = SpotifyEmbedPlayer()`), als Environment nach unten gereicht – wichtig, weil jede neue `WKWebView` eine eigene Wiedergabe stoppt.

**Zu bauen, analog:**
1. `TodApp/Core/Music/Embed/SoundCloudEmbedPlayer.swift`: neue `@Observable`-Klasse nach dem Vorbild von `SpotifyEmbedPlayer`. Lädt statt Spotifys iFrame-API SoundClouds Widget-JS-API (`https://w.soundcloud.com/player/api.js`) in einer unsichtbaren `WKWebView`, gesteuert per `SC.Widget`-JavaScript-Objekt (`play()`, `pause()`, `seekTo(ms)`, `getPosition`, `getDuration`), Events `SC.Widget.Events.READY`, `PLAY`, `PAUSE`, `FINISH`, `PLAY_PROGRESS` über denselben `WKScriptMessageHandler`-Bridge-Ansatz zurück nach Swift gemeldet. Embed-URL kann `EmbedURLBuilder.embedURL(for:)` (Fall `.soundcloud`, schon vorhanden in `TodApp/Core/Music/EmbedURLBuilder.swift`) weiterverwenden oder dafür leicht anpassen.
2. Neue Ansicht `SoundCloudOwnPlayer` in `TrackPlayerSheet.swift`, Geschwister von `SpotifyOwnPlayer`/`ApplePreviewPlayer`, nutzt dieselbe `Transport`-Komponente.
3. `TrackPlayerSheet.Player`-Enum bzw. die `case .widget`-Verzweigung (Zeile ~389) so ändern, dass sie `SoundCloudOwnPlayer` statt `soundCloudWidget(_:)`/`TrackEmbedView` zeigt. `TrackEmbedView` + `EmbedFallback` bleiben als Fallback erhalten, falls der neue Embed nicht lädt (`embedError`, analog zu Spotifys Fehlerfall).
4. App-weite Instanz analog Zeile 33 in `TodApp/App/TodApp.swift` anlegen und durchreichen.
5. `MiniPlayerBar.swift`, `private enum Speaker` (Zeile 32–33: `wholeSong, preview, embed, remote, provider`) um einen eigenen Fall für SoundCloud ergänzen (`embed` ist aktuell Spotify-spezifisch benannt/verwendet), damit der Mini-Player auch einen laufenden SoundCloud-Song korrekt anzeigt und pausieren/fortsetzen kann.

**Warum wichtig:** Ohne das sieht ein SoundCloud-Post in der Player-Vollansicht komplett anders aus als Apple-Music- und Spotify-Posts (fremdes Widget-Design statt der eigenen Waveform/Play-Button-Reihe aus dem Referenzdesign weiter oben) – bricht den einheitlichen Look, den der Rest des Screens schon hat.

## Auswahl-Screen (Song posten) ans allgemeine Design anpassen (25. September, Idee)

**Ist-Zustand (geprüft):** `PostSongView.swift` (Screen "Song posten", Suchen/Link-Modus mit Ergebnisliste) folgt dem "Glas statt Fläche"- und Cover-Art-Glow-Prinzip aus dem Abschnitt "Visuelle Ausrichtung – Modern Premium" oben noch nicht:

1. **Ergebnis-Zeilen sind flache Flächen** (`Button { ... }.background(Color.todSurface).clipShape(RoundedRectangle(cornerRadius: 12))`, um Zeile 178) statt `.ultraThinMaterial` + `todLine`-Rand, wie es der Rest der App inzwischen durchgängig macht (Mini-Player, Bewertungskarte in `SongFeedView.swift`, Player-Vollansicht).
2. **Der Suchen/Link-Umschalter ist der native `Picker(...).pickerStyle(.segmented)`** (Zeile ~86), nicht im App-eigenen Look – vergleichbar wäre die selbstgebaute `ratingSegment` in `SongFeedView.swift`: gleich breite Felder, Antipp-Skalierung, `todAccent`-Füllung für die aktive Wahl statt der System-Optik.
3. **Kein Cover-Art-Glow.** Sobald ein Kandidat ausgewählt ist (`model.selected`), könnte der Screen-Hintergrund wie in `SongDetailView.swift`/`SongFeedView.swift` per `CoverTint` die Farbe des gewählten Covers als weichen Verlauf hinter den Player legen, statt durchgehend `Color.todBackground` zu bleiben.

**Aufgabe für den Code-Agenten:** Diese drei Stellen an das etablierte Muster angleichen (`.ultraThinMaterial`-Karten, selbstgebauter Segment-Switch, `CoverTint`-Hintergrund sobald etwas ausgewählt ist) – keine neue Formensprache erfinden, nur das bestehende System nachziehen, das der Rest der App schon hat.

## Wichtig, jetzt: SoundCloud-Suche (25. September, Abend)

**Ist-Zustand (geprüft):** Es gibt aktuell **keine SoundCloud-Suche**. Im "Suchen"-Tab von `PostSongView.swift` geht die Anfrage nur an `provider.searchTracks` (Spotify, wenn verbunden) oder als Fallback an Apples iTunes-Suche (`ITunesCatalog`) – SoundCloud kommt dort nirgends vor. SoundCloud-Songs lassen sich bisher ausschließlich über den zweiten Tab "Link einfügen" hinzufügen: ein Link wird eingefügt, `SoundCloudOEmbedClient` löst ihn zu einem einzelnen Track auf (`soundcloud.com/oembed`, dazu ein zweiter Aufruf der öffentlichen Track-Seite für Länge/Titel). Das ist Metadaten-Auflösung für **eine bekannte URL**, keine Suche nach Songname/Artist.

**Wichtige Einschränkung, unbedingt beachten:** SoundClouds offizielle Such-API (`api.soundcloud.com/tracks?q=...`) braucht eine `client_id` aus einer App-Registrierung – und SoundCloud vergibt seit Jahren **keine neuen API-Zugänge** mehr an Drittentwickler (das steht auch schon als Kommentar im Code, `SoundCloudOEmbedClient.swift`: "SoundCloud no longer grants API credentials on request"). Eine echte Suche über die offizielle API ist also nicht einfach nachzubauen. Optionen für den Code-Agenten:

1. **Realistischer Weg, passend zum bereits bestehenden Muster:** SoundCloud stellt seine Suchergebnisse auch als normale, eingeloggt-öffentliche Webseite bereit (`https://soundcloud.com/search?q=<Suchbegriff>`). Genau wie `SoundCloudTrackPage` in `SoundCloudOEmbedClient.swift` bereits die öffentliche Track-Seite nach eingebetteten Meta-Tags/JSON durchsucht (für Länge und sauberen Titel), könnte eine neue `SoundCloudSearchClient` die Such-Ergebnisseite laden und die darin eingebettete Hydration-JSON (SoundCloud rendert die Trefferliste serverseitig in ein `<script>`-Tag) nach Titel, Künstler, Cover und Track-URL durchsuchen – ähnlich fragil wie der bestehende Page-Scrape-Ansatz (kann brechen, wenn SoundCloud sein Seiten-Markup ändert), aber ohne API-Key umsetzbar.
2. **Alternative, wenn 1. zu instabil ist:** Suche auf "Link einfügen" beschränkt lassen, aber die Eingabe erleichtern – z. B. automatisches Einfügen aus der Zwischenablage, wenn dort ein SoundCloud-Link liegt, sobald der Tab geöffnet wird.

**Korrektur (25. September, nach Recherche — die Einschätzung oben war veraltet):** Laut SoundClouds offizieller Doku (https://developers.soundcloud.com/docs/api/register-app) gibt es inzwischen wieder einen Selbstbedienungs-Weg zu echten API-Zugängen: mit einem **SoundCloud-Account plus kostenpflichtigem "Artist Pro"-Abo** (Preis auf der Checkout-Seite, https://checkout.soundcloud.com/artist) kann man im Browser oder über ein CLI-Tool (`sc-api-auth.mjs`, Node.js 18+, siehe SoundClouds GitHub) eine App registrieren und bekommt `client_id` + `client_secret`. Damit steht die echte `/tracks`-Such-API offen (Parameter `q`, dazu Filter wie `genres`, `access=playable`, `bpm[from]`, `duration[from]`, `limit` bis 200) — genau das, was Punkt 1 unten als "nicht einfach nachzubauen" beschrieben hatte.

**Entscheidung (25. September):** Das kostenpflichtige Artist-Pro-Abo wird vorerst nicht angeschafft — zu diesem Zeitpunkt nicht nötig. Bitte erstmal mit dem Scrape-Ansatz (Option 1/2 unten) weitermachen, ohne Kosten. Die Artist-Pro-Route bleibt als spätere Option festgehalten, falls das Scraping zu instabil wird.

**Das ändert die Aufgabe:** Bevor der fragile Scrape-Ansatz (Option 1 unten) angegangen wird, bitte zuerst prüfen, ob ein SoundCloud-Account mit Artist-Pro-Abo infrage kommt (Kosten tragbar? ähnlich wie beim Apple-Developer- und Spotify-Developer-Account, die für dieses Projekt schon vorhanden sind). Wenn ja: `client_id` genauso wie der bestehende `SpotifyClientID` über `Config/TodApp.xcconfig`/`Info.plist` einbinden (nicht ins Repo committen, siehe Sicherheits-Hinweise oben), und eine `SoundCloudSearchClient` bauen, die `GET https://api.soundcloud.com/tracks?q=<Suchbegriff>&client_id=<...>` aufruft und die Treffer in `TrackCandidate` mappt — deutlich robuster als HTML-Scraping. Der Scrape-Ansatz (Option 1/2 unten) bleibt nur als Fallback relevant, falls Artist Pro nicht infrage kommt.

**Vorgehen:** Bitte zuerst kurz `https://soundcloud.com/search?q=test` im Browser/curl anschauen, ob die Trefferliste tatsächlich serverseitig im HTML steckt (wahrscheinlich ja, wie bei der Track-Seite) oder rein per JavaScript nachgeladen wird (dann bräuchte es einen Web-View-Ansatz statt eines einfachen HTTP-Requests) – das entscheidet, ob Option 1 mit einem simplen `URLSession`-Request funktioniert oder mehr Aufwand braucht.

## Vier weitere Ideen/Aufgaben (25. September, Abend)

### 1. Glas bei Player + den beiden Icons in der Nav-Leiste

**Ist-Zustand (geprüft):** Ist eigentlich schon so umgesetzt, seit dem letzten Durchgang durch `RootNavBar.swift`/`MiniPlayerBar.swift` (deutlich weiterentwickelt seit dem 24. September – jetzt mit einer eigenen `LiquidGlass`-Abstraktion für iOS' neues Glas-Material, mit `.ultraThinMaterial`-Fallback für ältere Systeme). Sowohl die Home-/Gruppen-Buttons (`ItemGlass`) als auch die Mini-Player-Pille (`MiniPlayerBar.card()`, `.liquidGlass(in: Capsule(), ...)`) sind als Glas gebaut. Falls es auf dem Gerät trotzdem nicht glasig aussieht: bitte Screenshot schicken, dann gezielt nachschauen (könnte an `LiquidGlass.isAvailable`/der jeweiligen iOS-Version liegen) – aus dem Code allein sieht das schon richtig aus.

### 2. Wischen Home ↔ Gruppen

**Ist-Zustand (geprüft):** Bereits umgesetzt, ebenfalls in `RootNavBar.swift` (`RootNavSwipe`, `slide`-Gesture) – sowohl als Fingerbewegung entlang der zusammenhängenden Kapsel (nichts spielt) als auch als Wisch-Geste, wenn die Leiste auseinandergezogen ist (etwas spielt). Nichts mehr offen hier.

### 3. Idle-Zustand der Pille: "+"/Suche-Button mit Lesezeichen (neu)

**Ist-Zustand (geprüft):** Wenn nichts spielt, ist die Mini-Player-Pille aktuell komplett unsichtbar/0 breit (`MiniPlayerBar` zeigt nichts, `RootNavBar` lässt Home und Gruppen zu einer gemeinsamen Kapsel zusammenfließen) – in der Mitte passiert dann nichts.

**Neue Idee:** Wenn kein Song spielt, in der Mitte statt der leeren Fläche einen "+"/Such-Button zeigen. Ein Tap öffnet die Song-Suche (denselben Suchen-Modus wie in `PostSongView.swift`), aber **ohne Zwang, sofort zu posten** – zusätzlich soll man dort einen Song "mit Lesezeichen versehen" können, um ihn sich für später zu merken (nicht zwingend heute posten).

**Achtung, das ist mehr als ein UI-Handgriff:** Es gibt aktuell **kein** Konzept für "gemerkte"/Lesezeichen-Songs im Datenmodell (keine `Bookmark`- oder `SavedSong`-Struktur, kein Repository-Case dafür – geprüft, nichts gefunden). Für den Code-Agenten heißt das:
- Ein neues, einfaches Modell (`SavedSong`/`Bookmark`: id, Song-Daten wie bei `TrackCandidate`, gespeichert von, Zeitpunkt) und eine Ablage dafür (fürs Prototyp-Stadium reicht vermutlich In-Memory im `AppStore`, analog zu anderem lokalem State, bevor es – wie in Abschnitt 7 oben beschrieben – eventuell in Supabase wandert).
- Eine kleine Liste/Sheet, in der gemerkte Songs später wieder auftauchen (z. B. um von dort aus doch zu posten).
- Den "+"-Button selbst in `RootNavBar`/`MiniPlayerBar` einbauen, sichtbar nur wenn `nowPlaying.isCardShown == false`.

Bevor das umgesetzt wird: kurz klären, ob "Lesezeichen" wirklich ein eigenständiges Feature werden soll, oder ob eine einfachere erste Version reicht (z. B. nur der Sprung in die Suche, das Merken kommt später).

### 4. Home-Screen: "Anhören" wird ein Play-Button

**Ist-Zustand (geprüft):** `TodApp/Features/Today/TodayView.swift`, Zeile ~183: der eigene gepostete Song hat einen **Text-Button** ("Anhören", oder "Kommentare" ohne Link), gebaut mit `TodPrimaryButtonStyle()` – ein breiter Pill-Button mit Schrift, kein Icon.

**Aufgabe:** Diesen Text-Button durch einen echten Play-Button (Icon statt/zusätzlich zu Text) ersetzen, im Stil des bestehenden `QuickPlayButton` (runder `todAccent`-Kreis mit Play-/Pause-Symbol und Fortschrittsring, siehe `TodApp/Features/Player/QuickPlayButton.swift`) – damit sieht das Anhören auf Home genauso aus wie das Quick-Play auf den Bewertungs-Karten, statt wie ein reiner Text-Link. Für "Kommentare" (kein Link vorhanden) bleibt vermutlich ein Text-Button sinnvoller, da es dort nichts abzuspielen gibt.

## Zwei weitere Punkte (25. September, Abend, spät)

### 1. Gruppenwechsel auf Home: Übergang soll smoother sein

**Ist-Zustand (geprüft, `TodayView.swift`):** Im `body` steht der Inhalt (Streak-Kachel, dann `if let song = mySong { songCard(song) } else { postPrompt }`) direkt in der `VStack(spacing: 22)`, ohne `.id(...)`, `.transition(...)` oder `.animation(value: store.currentGroupID)`. Wechselt man über die `GroupSwitcherBar` die Gruppe, ändert sich `store.currentGroupID` → `mySong`/`group` ändern sich sofort und der komplette Block (Streak-Zahl, Songkarte/Post-Prompt) springt hart um. `GroupSwitcherBar.swift` hat zwar selbst schon `.animation(.snappy, value: store.currentGroupID)`, aber das betrifft nur die Avatar-Reihe, nicht den restlichen Home-Inhalt darunter.

**Aufgabe:** Den Inhaltsblock unterhalb der `GroupSwitcherBar` (Streak-Kachel + `songCard`/`postPrompt`) beim Gruppenwechsel weich überblenden statt hart springen lassen. Vorschlag:
- Auf die `VStack(spacing: 22)` (oder gezielt auf die Streak-Kachel und den `songCard`/`postPrompt`-Bereich) `.id(store.currentGroupID)` setzen, damit SwiftUI den Block als neue Identität behandelt, kombiniert mit `.transition(.opacity)` und `.animation(.snappy, value: store.currentGroupID)` auf dem Elternview.
- Alternativ nur den `if let song = mySong { ... } else { postPrompt }`-Zweig in `.transition(.opacity.combined(with: .move(edge: .bottom)))` wrappen und mit derselben `.animation(.snappy, value: store.currentGroupID)` versehen, damit es zur bereits vorhandenen Avatar-Animation passt (gleiche Timing-Kurve wie in `GroupSwitcherBar.swift`).
- Wichtig: Referenz ist `store.currentGroupID`, nicht `store.currentGroup` (Group ist evtl. nicht `Equatable`/`Hashable` in der Form, die `.animation(value:)` braucht).

Betroffene Datei: `TodApp/Features/Today/TodayView.swift`, `body`, ca. Zeile 25-45.

### 2. Track-Abschnitt-Auswahl-Screen: linksbündig → zentriert wie Rest der App

**Ist-Zustand (geprüft, `TrackPlayerSheet.swift`, `compactView`, Zeile 262-291):** Der komplette Screen ist `VStack(alignment: .leading, spacing: 16)` mit `.frame(maxWidth: .infinity, alignment: .leading)` — Titel/Interpret, `TrackSectionPicker` (Waveform-Auswahl), `routePlayer`, `platformPills` sind alle linksbündig. Das ist der Screen aus dem Screenshot (wird in `PostSongView.swift` gezeigt, sobald ein Kandidat ausgewählt ist und `sectionEditing` gesetzt wird). Im Vergleich dazu ist `fullView` (die normale Player-Vollansicht) zentriert (`VStack(spacing: 18)`, Cover/Titel/Interpret mittig). `platformPills` selbst unterscheidet intern schon zwischen `isFullView ? .center : .leading` — dieser Screen läuft also aktuell im `.leading`-Zweig.

**Aufgabe:** `compactView` auf zentrierte Ausrichtung umstellen, damit er zum Rest der App passt:
- Äußere `VStack(alignment: .leading, ...)` → `VStack(alignment: .center, ...)`, `.frame(maxWidth: .infinity, alignment: .leading)` am Ende → `.frame(maxWidth: .infinity)` (kein `alignment: .leading` mehr).
- Titel/Interpret-Block (`VStack(alignment: .leading, spacing: 4)`, Zeile 264) → `alignment: .center` und Texte mit `.multilineTextAlignment(.center)`.
- `TrackSectionPicker` selbst prüfen, ob er intern linksbündige Labels/Texte hat (z.B. "Track-Abschnitt wählen"-Beschriftung, Hinweistext zur Waveform) — diese ebenfalls zentrieren, soweit es dort feste `alignment: .leading` gibt.
- `platformPills` braucht keine Änderung, da es über `isFullView` bereits automatisch auf `.center` mitzieht, sobald der äußere Rahmen nicht mehr `.leading` erzwingt — nur prüfen, ob `isFullView` hier korrekt `false` bleibt oder ob eine neue Bedingung nötig ist, damit die Center-Ausrichtung greift ohne `isFullView` umzudefinieren.
- Ziel: gleiche optische Sprache wie `fullView` (mittig), aber weiterhin der kompaktere Screen (kein Cover-Bild, kein voller Player) für die Abschnitts-Auswahl beim Posten.

Betroffene Datei: `TodApp/Features/Player/TrackPlayerSheet.swift`, `compactView`, Zeile 262-291 (ggf. `TrackSectionPicker`-Komponente separat prüfen).

## SoundCloud: was erlaubt ist (26. September)

Geprüft gegen SoundClouds API Terms of Use (https://developers.soundcloud.com/docs/api/terms-of-use). Keine Rechtsberatung, sondern der Stand der Bedingungen.

**Suche über die Suchseite (`SoundCloudSearchClient`) — Verstoß gegen die Bedingungen.** Abschnitt 10: „You must not employ scraping or similar techniques to copy, aggregate, repurpose, republish or otherwise make use of any data from the SoundCloud platform.“ Strafbar ist das nicht und es gibt auch kein Urheberrechtsproblem (es werden nur Titel, Uploader und Links gelesen, keine Musik). Möglich sind aber eine Abmahnung oder Sperre durch SoundCloud und eine Ablehnung durch Apple (App Review 5.2: fremde Inhalte nur mit Erlaubnis).
- **Umgesetzt:** ein Schalter, `SoundCloudSearchPolicy` in `TodApp/Core/Music/SoundCloudTerms.swift`. Die Suche läuft in Debug-Builds und auf TestFlight, **im App-Store-Build ist sie aus**. Erkannt wird das über `AppTransaction` (TestFlight = Sandbox). Kann die App Store die Frage nicht beantworten, gilt „App Store“, die Suche bleibt also aus.
- Im App Store bleiben SoundCloud-Songs über „Link einfügen“ möglich. Das nutzt oEmbed, eine offizielle Schnittstelle.
- Für eine SoundCloud-Suche im App Store braucht es einen offiziellen API-Zugang (siehe Artist Pro oben) und dann `api.soundcloud.com/tracks?q=`.

**Versteckter Player (`SoundCloudEmbedPlayer`) — Grauzone, entschärft.** Das offizielle Widget und seine JS-API zu nutzen ist erlaubt. Abschnitt 8 verlangt aber, dass die App den Uploader als Urheber nennt, SoundCloud als Quelle angibt und einen sichtbaren Link zum Sound auf soundcloud.com hat. Abschnitt 10 verbietet, SoundClouds Werbung zu stören. Ein Player mit Größe null blendet aus, was das Widget selbst zeigen würde.
- **Umgesetzt:** Unter den Bedienelementen von `SoundCloudOwnPlayer` steht jetzt eine Zeile „Von <Uploader> · auf SoundCloud ↗“ (`SoundCloudAttribution`). Ein Tap öffnet den Song auf soundcloud.com. Die „SoundCloud“-Pille darunter verlinkt ebenfalls dorthin.
- **Offen:**
  - Das Symbol ist noch eine orange Wolke (SF Symbol) und nicht SoundClouds offizielles Logo. Die Freigabe für offizielle Grafiken galt bisher nur für Apple und Spotify. Für SoundClouds Logo (Brand-Guidelines auf soundcloud.com/press bzw. developers.soundcloud.com) braucht es eine eigene Freigabe.
  - Abschnitt 5 verbietet „alternative“ Hördienste, die Inhalte vieler Uploader zu einem On-Demand-Streamingangebot bündeln. TodApp teilt einzelne Songs in kleinen Gruppen, das ist eher kein solcher Dienst, aber nicht eindeutig.
  - Vor der Veröffentlichung im App Store abwägen, ob SoundClouds Widget statt mit Größe null klein, aber sichtbar gezeigt werden soll.
