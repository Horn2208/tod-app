---
tags: [todapp, übergabe]
---

# Übergabe — Stand 16. September 2026, nachmittags

Committet und gepusht. Branch `feat/music-embeds`, **430 Tests grün**, keine
Build-Warnungen. Nicht committet, weil aus einer anderen Sitzung und noch in Arbeit:
„Ohne Musikdienst weiter“ mit iTunes-Suche als Rückfall (vorgemerkt in `AppStore`,
`SpotifyProvider`, `SignInView`, `MusicKitCatalog`). Offener PR:
[soft233-ttv/tod-app#1](https://github.com/soft233-ttv/tod-app/pull/1).

## Was gemacht ist

Der Redesign-Prompt (`docs/2026-09-04-redesign-prompt-home-gruppen-profil.md`) ist
abgearbeitet — Reveal am Kalendertag, Kommentare, Profil, Chat als Gruppen-Hub,
Gruppeneinstellungen mit Einlade-Berechtigung und Saisontabelle, Swipe-Feed mit
Bewertungs-Notizen, Rangliste auf echten Zahlen, und der eigene Spotify-Player über
die iFrame API mit Wellenform.

**Tägliche Erinnerungen (Prompt Abschnitt 6).** Um 15 Uhr zum Posten, nur solange
es heute in mindestens einer Gruppe noch keinen Song von dir gibt — die Nachricht
nennt genau diese Gruppen. Um 20 Uhr zum Voten, an alle. Die Regel steht in
`DailyReminders` und plant eine Woche Einzel-Erinnerungen statt eines
wiederholenden Auslösers: einen einzelnen Tag eines wiederholenden Auslösers kann
man nicht absagen. Neu geplant wird beim Laden der Gruppen, nach jedem Post und
wenn die App wieder nach vorn kommt; ein Post in der letzten offenen Gruppe nimmt die
heutige 15-Uhr-Erinnerung zurück. Eingeschaltet wird im Profil (Karte
„Erinnerungen“), nicht beim Start — die Systemabfrage kommt nur ein einziges Mal.
Im Simulator belegt: die Spur (`category == "reminders"`) meldet nach dem Start
14 geplante Erinnerungen, „not allowed, none scheduled“, weil noch niemand zugestimmt
hat. **Offen:** dass iOS sie nach der Zustimmung wirklich zustellt, ist ungesehen —
die Zustimmung gibt der Nutzer selbst.

**Apple-Music-Vorschau ohne Account (Prompt 3g, der Teil ohne MusicKit).** Ein
Spotify-Song spielt Apples Vorschau nativ über `AVPlayer` (`PreviewPlayer`), wenn der
Katalog dieselbe Aufnahme hat — ohne Web-View und ohne Login. Gesucht wird über die
offene iTunes-Search-API (`ITunesCatalog`), entschieden von `CatalogMatch`: Titel und
Hauptkünstler müssen übereinstimmen, die Länge auf 3 s genau. `CatalogResolver`
merkt sich Treffer und „nicht im Katalog“, aber keine Netzfehler. Ohne Treffer spielt
Spotifys Embed wie bisher. Eine Spotify-Anmeldung im Player behält das Embed, weil
die ganze Songs bringen kann und Apples Vorschau nie. Beim Posten wandern die ISRC
(aus Spotifys `external_ids`) und die Apple-Music-ID mit. MusicKit dockt später als
zweiter `MusicCatalog` und als eigener Player an; die Wahl steht in
`TrackPlayerSheet.player(for:catalog:spotifyWebSession:)`.

Gemessen, bevor gebaut wurde:
- **Apple-Vorschauen sind 30 Sekunden lang**, nicht „ca. 90“, wie der Prompt sagt —
  vier Songs von 200 bis 354 s, alle 30,0 s. Einen gewählten Abschnitt erreicht die
  Vorschau also so wenig wie Spotifys; der Player sagt das.
- **Die iTunes-API kennt, was verkauft wird, nicht was Apple Music streamt.** Frank
  Oceans „Nights“ fehlt samt Album „Blonde“, auch unter 193 Songs des Künstlers. Die
  Textsuche setzt stattdessen Martin Garrix' „Ocean (feat. Khalid)“ auf Platz 1 —
  deshalb eine Regel statt des ersten Treffers, getestet an genau diesen Listen.
- `lookup?id=` liefert die Vorschau zuverlässig; eine gespeicherte ID wird
  nachgeschlagen statt neu gesucht.

Im Simulator belegt (Spur `category == "preview"`): „Blinding Lights“ nimmt den
Apple-Weg, der Player zeigt 0:30 schon vor dem Abspielen, spielt 30,1 s bis zum Ende
und startet nach dem Ende auf Play wieder bei 0. Einmal lagen zwischen `load` und
`ready` 9 Sekunden — ob das am Netz lag, ist offen. **Ungesehen:** der Mini-Player
während einer Apple-Vorschau. Zwischen Play, Schließen des Sheets und Screenshot
vergingen jedes Mal über 30 Sekunden, die Vorschau war dann schon vorbei. Ebenfalls
nur durch Tests belegt: der Rückfall aufs Spotify-Embed ohne Treffer — im Seed hat
jeder Spotify-Song einen.

**Auch ein Song ohne Link bekommt einen Player**, wenn Apple ihn unter Titel und
Künstler kennt — das ist der Sinn von „Apple Music ist die Hauptquelle“: Die Wiedergabe
hängt nicht mehr an einem Spotify-Link. `TrackPlayerSheet` nimmt die Quelle jetzt
optional, `CatalogResolver` wird über `CatalogKey` angesprochen (Link, sonst Titel und
Künstler), und findet der Katalog nichts, steht dort „Nichts zum Abspielen“ statt einer
Lücke. Betrifft die meisten Songs im Seed, die nie einen Link hatten.

Im Simulator belegt: „Passionfruit“ von Drake, im Seed ohne Link, bekommt den
Apple-Player mit 0:30 und „In Apple Music öffnen“ — und keinen Spotify-Link, weil es
keinen gibt. Die Spur zeigt `load 1440892167`, genau die ID, die die iTunes-API beim
Messen für diesen Song lieferte. Gespielt hat er auch: `play` um 03:06:08,97,
`end` um 03:06:39,21, also die vollen 30 Sekunden.

Nachgeschärft nach eigener Durchsicht: Die Katalogabfrage gibt nach 5 s auf (sonst
stand bei langsamem Netz eine Minute lang „Player lädt“, bevor das Embed dran war),
und bis die Vorschau bereit ist, sagt der Player „Vorschau lädt …“ statt ein
Pause-Symbol über Stille zu zeigen.

**Tastatur (Prompt Abschnitt 5).** Ein Tipp neben ein Textfeld schließt die
Tastatur, ein Tipp ins Feld nicht, und Ziehen in einer Liste zieht sie herunter —
an allen neun Textfeldern der App. Das macht ein Modifier-Paar in
`Features/Shared/KeyboardDismissal.swift`: `dismissesKeyboardOnTap()` für die
Fläche, `keepsKeyboardOnTap()` für Felder darin, die ihre Position melden, damit ein
Tipp hinein nicht im selben Moment wieder schließt. Die Eingabeleiste im Chat und
das Antwortfeld unter einem Song liegen bewusst außerhalb der Fläche: „Senden“
lässt die Tastatur offen für die nächste Zeile. Die Suche beim Posten trägt auf der
Taste „Suchen“; dass Return dort die Tastatur schließt, ist SwiftUIs
Standardverhalten und nicht eigens geprüft. Im Simulator belegt an Profil, Chat
und dem Notizfeld im Bewertungs-Feed — dem heikelsten Fall, weil das Feld innerhalb
der Fläche liegt: nach einem Tipp ins Feld kommt getippter Text an, nach einem
Tipp daneben nicht mehr. Die Bewertungsknöpfe im Feed reagieren trotz des
zusätzlichen Tipp-Erkenners weiter („Gut“ gesetzt, Zähler auf 1 von 4). Die
Gruppensuche ist nur gebaut, nicht angetippt.

## Was als Nächstes ansteht

**Der Premium-Weg im Player ist gebaut, aber ungeprüft** (`42ffec0`). Der Nutzer
meldet sich im Profil unter „Spotify“ selbst an — seit dem Zusammenlegen dieselbe
Anmeldung wie für Suchen und Posten; danach
„Blinding Lights“ öffnen (der Seed wählt dort 1:00–1:30) und die `embed`-Spur lesen:
Länge um 200 s statt 30 und Wiedergabe ab 60 s heißt, es funktioniert.

**Die Kursänderung im Prompt-Dokument ist erst zum Teil umgesetzt** — der Teil, der
ohne bezahlten Account geht, steht oben. Der Nutzer hat
Abschnitt 3g neu geschrieben: Apple Music über MusicKit als Hauptweg, Spotify nur
noch Suche über den Client-Credentials-Flow, Abgleich per ISRC. Die Änderung liegt
uncommittet im Arbeitsverzeichnis. Drei Dinge daran sind vor dem Bauen zu klären:
- **Client Credentials braucht das Client-Secret** — in der App oder hinter einem
  Proxy. Genau das wurde abgeschafft (PKCE, Proxy weg, Secret zum Widerrufen).
- **Einen ISRC-Abgleich bietet die offene iTunes-API nicht an.** Apples Dokumentation
  nennt für `lookup` keinen ISRC-Parameter, und `lookup?isrc=` gab null Treffer —
  allerdings mit einer ISRC aus dem Gedächtnis; die Gegenprobe mit einer belegten
  scheiterte, weil MusicBrainz mit 503 antwortete. Der ISRC-Endpunkt ist Teil der
  Apple-Music-API und braucht den Developer-Token, also den bezahlten Account.
- Das Dokument sagt, ganze Songs über ein Spotify-Embed gebe es nur im
  Desktop-Browser. Stimmt das, scheitert der Premium-Test oben — er ist damit
  zugleich der Test dieser Behauptung.

**Ein ungeklärter Player-Fehler.** Beim Nutzer hing der erste Druck auf Play:
Pause-Symbol, 0:00, kein Fortschritt. Die App lief zu dem Zeitpunkt seit über einer
Stunde. Das Log zeigt genau zwei JavaScript-Aufrufe — das Laden beim Öffnen des Songs
und den Druck 5,99 s später —, beide zugestellt; der Web-Prozess war weder beendet
noch schlafengelegt. Frisch gestartet spielt derselbe Druck zuverlässig, auch nach
dem Umbau unten. Auch im Langzeit-Test des Nutzers — 38 Minuten Laufzeit —
spielte der erste Druck; der Hänger trat nicht wieder auf.

Was dagegen gebaut wurde, erklärt ihn **nicht**. `EmbedPlayGate` hält Play zurück, bis
Spotifys eigenes `ready` für den geladenen Song kommt. Gemessen kommt `ready` aber
0,78 s nach dem Laden — der Druck nach 5,99 s lag weit dahinter und wäre von der
Sperre nicht aufgehalten worden. Die Commit-Nachricht zu `d39edf6` behauptet das
Gegenteil und ist in dem Punkt falsch. Die Sperre bleibt, weil sie ein echtes, aber
kurzes Fenster schützt.

**So geht es weiter:** Der Player schreibt eine Spur ins System-Log — Laden, Spotifys
`ready`, Rückfall-Timer, gesendetes oder zurückgehaltenes Play, Fehler des Embeds.
Tritt der Fehler wieder auf, sofort lesen mit

    xcrun simctl spawn booted log show --last 10m --style compact \
      --predicate 'subsystem == "com.lennetschierhorn.TodApp" AND category == "embed"'

Auffälligster Unterschied zwischen Fehlschlag und Erfolg bisher: die Laufzeit der App,
über eine Stunde gegen zwei Minuten.

**Neustart nach dem Ende funktioniert.** Ein kurzer Tipp auf Play bei 0:30 / 0:30 baut
die Seite neu auf, Spotify meldet 0,17 s nach dem Laden „bereit", das zurückgehaltene
Play geht raus und die Vorschau läuft von vorn — belegt über die Spur und am
Bildschirm, und vom Nutzer bestätigt: ein Klick auf Play startet neu und spielt durch,
ein Klick auf die Wellenform springt an die Stelle und spielt von dort. Offen ist ein
Fenster aus dem Nutzertest: rund eine Minute lang kamen
kurze Tipps am Ende **gar nicht im Code an** — kein JavaScript-Aufruf, kein Neuaufbau —,
erst ein langes Drücken. Kurze Tipps desselben Nutzers wenige Minuten später kamen
an, und im Nachtest spielte jeder Klick auf Play; nachstellen ließ es sich nicht —
am wahrscheinlichsten ein Klick neben den Kreis, belegt ist das nicht. Nicht aus Screenshots auf den Verlauf einer
30-Sekunden-Wiedergabe schließen — die Spur lesen.

Danach offen aus dem Prompt: **Apple Music über MusicKit** — braucht den bezahlten
Apple-Developer-Account, liegt also beim Nutzer. SoundCloud bleibt beim Embed-Widget;
für die iFrame API gibt es dort kein Gegenstück.

**Apple Music über MusicKit — vorbereitet, wartet auf die Freischaltung des
Developer-Accounts.** Gebaut ist, was ohne aktiven Account geht:
- `MusicKitCatalog` fragt Apple Musics Katalog: erst die gespeicherte ID, dann die
  ISRC (gegen die Länge geprüft), dann die Textsuche. Die ISRC eines Posts reicht
  jetzt bis dorthin.
- `FallbackCatalog` fragt MusicKit nur, wenn Apple Music erlaubt ist, und fällt bei
  einem *Fehler* auf die iTunes-Suche zurück — bis zur Freischaltung wirft MusicKit
  bei jeder Anfrage, also bleibt bis dahin alles wie es war.
- `AppleMusicAccess` liest Erlaubnis und Abo (`nicht gefragt / ausgeschaltet / ohne
  Abo / ganze Songs`) und folgt dem Abo, solange die App läuft.
- `AppleMusicPlayer` spielt ganze Songs über `ApplicationMusicPlayer`, ab dem gewählten
  Abschnitt: der Eintrag in der Warteschlange trägt `startTime` selbst. Geladen wird
  erst beim Druck auf Play, nie beim Öffnen — das Einreihen würde sonst die laufende
  Wiedergabe abwürgen. Protokoll: `category == "applemusic"`.
- Die Weiche wählt ganze Songs vor Vorschau und Spotify-Embed, sobald das Abo sie
  spielt; das Profil hat die Karte „Apple Music“; der Mini-Player kennt den vierten
  Sprecher; der Berechtigungstext steht in der Plist.

**Ungeprüft, und vorher nicht prüfbar:** jede echte MusicKit-Anfrage, die ISRC-Suche
gegen den echten Katalog und die Wiedergabe ganzer Songs. Getestet sind die reinen
Regeln — Weiche, Suchreihenfolge, Ausweichen, Abo-Stand. Ganze Songs laufen nur auf
einem echten iPhone mit Apple-Music-Abo, nie im Simulator.

**Eine Spotify-Anmeldung statt zwei.** Suchen und Posten meldeten sich über das
System-Browserfenster an (`ASWebAuthenticationSession`), dessen Cookies die App nie
sieht — ganze Songs im Player brauchten deshalb eine zweite Anmeldung im Web-View der
App. Die Anmeldung läuft jetzt selbst in einem Web-View auf dem Speicher, aus dem das
Embed spielt (`WebAuthentication`): Die Rückleitung auf `todapp://` wird abgefangen,
der Code wie bisher getauscht, und die Spotify-Sitzung liegt schon dort, wo der Player
sie braucht. Beim Abmelden werden die Spotify-Cookies gelöscht; sonst nähme die nächste
Anmeldung still das alte Konto — genau das hatte vorher die „ephemere“ Browser-Sitzung
verhindert. Im Profil gibt es eine Karte „Spotify“ mit einem Knopf.
**Einschränkung:** „Mit Google, Apple oder Facebook fortfahren“ verweigert in
eingebetteten Web-Views oft den Dienst; E-Mail und Passwort funktionieren.
**Ungeprüft:** eine echte Anmeldung bis zum Ende — die Zugangsdaten gibt der Nutzer
selbst ein.

**Home, der Rest aus Prompt-Abschnitt 1.**
- **Streak-Kalender:** Ein Tipp auf die Streak öffnet eine Monatsansicht (Montag
  zuerst, deutsch), durch die man bis zum Monat des ersten Posts zurückblättert; jeder
  Tag mit Post ist gefüllt, heute umrandet, kommende Tage blass. Das Raster rechnet
  `StreakCalendar`, getestet ohne SwiftUI — auch ein Post um 23:59 bleibt an seinem Tag.
- **Nach dem Posten** geht Home direkt in den Bewertungs-Feed der laufenden Runde.
  Erkannt wird ein neuer Post daran, dass „dein Song“ nach dem Schließen des Sheets ein
  anderer ist als beim Öffnen — ein abgebrochenes Sheet führt nirgendwohin.
- **Gruppen-Switcher** oben auf Home, sobald man in mehr als einer Gruppe ist: die
  Gruppenbilder als Kreise, die gewählte Gruppe groß mit Story-Ring und immer in der
  Mitte, direkt über ihrem Namen; die anderen kleiner und gedimmt daneben. Ein Tipp
  oder ein Wisch holt eine Gruppe in die Mitte und wählt sie. Jeder Kreis belegt gleich
  viel Platz, der Größenunterschied ist nur gezeichnet (`scaleEffect`) — so steht der
  gewählte genau mittig, und das Emoji wächst mit, statt zu springen. Streak und Song
  folgen der gewählten Gruppe. Das Gruppenbild zeichnet
  jetzt überall `GroupAvatar` statt drei Kopien.

**Gruppen-Ansicht, der Rest aus Prompt-Abschnitt 2.**
- **Song-Blase über den Kreisen:** Wer heute gepostet hat, bekommt über seinem Kreis
  eine kleine Blase mit Titel und Künstler. Über jedem Kreis bleibt Platz dafür, auch
  ohne Blase, damit die Gesichter auf einer Linie stehen. VoiceOver nennt den Song mit.
- **Ein Tipp auf eine Person öffnet den Bewertungs-Feed bei ihrer Karte**, nicht mehr
  eine einzelne Song-Ansicht. Die Story-Leiste zeigt Leute aus allen Gruppen, der Feed
  eine: Der Tipp wählt deshalb erst die Gruppe des neuesten Posts und öffnet dann die
  passende Runde — heute den laufenden Feed, gestern das Reveal. Ein älterer Song liegt
  in keiner Runde mehr und öffnet wie bisher allein. Die Regeln stehen in
  `GroupsFeed.storyTarget`/`storyBubble`, getestet mit festen Daten, weil „heute“ an
  der echten Uhr um Mitternacht mitten im Lauf kippen würde.
- `SongFeedView(round:startAt:)` öffnet bei einer bestimmten Karte, indem diese nach vorn
  rückt (`GroupsFeed.feedOrder`); die übrigen folgen in ihrer gewohnten Reihenfolge.

**Mini-Player, aus Prompt-Abschnitt 3.** Statt einer Leiste am unteren Rand schwebt eine
abgerundete Glas-Karte über der Tab-Leiste, mit Abstand zu den Seiten: links das Cover,
daneben Titel und Künstler mit einem kleinen Zeichen für den Dienst, der gerade spielt,
rechts ein runder Play-/Pause-Knopf in der Akzentfarbe mit dem Fortschritt als Ring
darum; das Cover liegt zusätzlich gedimmt dahinter. Der Prompt wollte zuerst nur den
Knopf in der Mitte — auf dem iPhone ausprobiert, sollen Titel und Cover sichtbar sein
(Wunsch vom 16. September). Titel und Künstler kommen vom Post, sonst vom Katalog. Nach einer Pause bleibt die Karte noch vier Sekunden stehen, mit
einem Knopf zum Weiterspielen (`MiniPlayerVisibility`); ein Weiterspielen in der Zeit
bricht das Ausblenden ab. Ein Tipp auf die Karte öffnet den Song wieder — dafür trägt der
Player beim Druck auf Play den Post in `NowPlaying` ein, weil sich aus einer Vorschau oder
einem ganzen Song nicht sicher zurückrechnen lässt, zu welchem Post sie gehören. Klingt
ein Song, der noch gar kein Post ist (beim Posten), bietet die Karte nichts zum Tippen
statt eines Tipps ohne Wirkung. Vorher war `onOpen` leer: der Tipp tat nichts.
Die Platzierung ist gemessen, nicht gesetzt: Nur darübergelegt, wie der Prompt es
verlangt, verdeckte die Karte den unteren Rand dessen, was darunter lag — im Feed „0 von
4 bewertet“. Als Sicherheitsabstand am Navigations-Stapel jedes Tabs erreichte sie die
darauf geschobenen Bildschirme nicht, der Feed blieb verdeckt. Jetzt schwebt die Karte,
und die Bildschirme mit etwas am unteren Rand machen ihr selbst Platz
(`leavesRoomForMiniPlayer`, auf Home, Gruppen, Chat, Feed, Rangliste, Einstellungen).
Die genauen vier Sekunden Nachlauf sind nur per Test belegt; mit einer Rundenlaufzeit
von rund zehn Sekunden lassen sie sich im Simulator nicht beobachten.

**Begründung im Feed, auf der Tastatur.** Beim Tippen in „Warum?“ rutschte die Karte unter
den Titel, und von unten schaute die nächste herein (Screenshot vom iPhone, im Simulator
nachgestellt): Mit Tastatur schrumpfte jede Seite auf den Platz darüber, und das Feld
wurde ins Bild gescrollt. Jetzt ignoriert der Feed die Tastatur, und geschrieben wird in
einer Leiste, die auf der Tastatur sitzt (`NoteComposer`). Das Feld auf der Karte ist
nur noch ein Knopf, der sie öffnet. Die Leiste speichert beim Schließen — „Fertig“,
Return, Tipp daneben oder Wisch —, damit keine halbe Begründung verloren geht. Die Karte
liest die Begründung jetzt aus dem Store statt einer Kopie vom Erscheinen: Die Kopie war
nach dem Speichern veraltet, und eine geänderte Bewertung hätte die alte mitgeschickt.

**Aus der Sitzung vom 14. September nachgezogen.** `SourceAttribution.swift` und
`ChatMention.swift` samt Tests lagen im Repo, standen aber nicht im Xcode-Projekt —
gebaut und getestet wurden sie nie. `xcodegen generate` hat sie aufgenommen (fünf Tests
mehr). Dass `ChatMention.target` noch niemand benutzte, ist im nächsten Absatz
nachgezogen. Die Quellen-Zeichen sind SF-Symbol-Platzhalter, keine Marken-Logos.

**Cover-Farbe als Schimmer, aus dem Visuellen Abschnitt des Prompts.** Hinter deinem Song
auf Home und hinter jeder Karte im Feed leuchtet jetzt die Farbe, die das Cover selbst
trägt, statt der aus dem Titel abgeleiteten (`CoverColor`). `ArtworkColor` liest sie aus
einem 16×16-Vorschaubild: Grau, fast Schwarz und fast Weiß zählen nicht, der Rest wird
nach Farbton gruppiert, und es gewinnt die Gruppe mit der meisten Farbe — ein kräftiges
Motiv vor großem, blassem Grund schlägt den Grund. Übernommen wird nur der Farbton, mit
fester Sättigung und Helligkeit, damit weißer Text darauf lesbar bleibt. Getestet ohne
SwiftUI, einmal auch über echte PNG-Bytes. `CoverPalette` liest jedes Cover einmal
(über dieselbe `URLSession` wie `AsyncImage`, also meist aus dem Cache) und merkt sich
das Ergebnis; nur ein fehlgeschlagener Download wird erneut versucht. Bis das Cover
gelesen ist und ohne Cover gilt weiter die abgeleitete Farbe (`CoverTint`). Im Simulator
geprüft mit einem gerade geposteten „Blinding Lights“: warm statt des früheren Lila.

**Signing-Team in `project.yml`.** Das Team (`B892A3M49U`) war nur in Xcode gesetzt, und
jedes `xcodegen generate` hat es wieder gelöscht. Jetzt steht es in `project.yml`
(`DEVELOPMENT_TEAM`), damit die App nach einem Neu-Erzeugen weiter aufs iPhone geht.

**Song-Erwähnung im Chat, antippbar.** Die Song-Karte unter einer Nachricht ist jetzt ein
Knopf und landet dort, wo `ChatMention.target` es sagt: ein Song von heute im laufenden
Feed, einer von gestern im Reveal — beide an seiner Karte, mit demselben `FeedTarget`
wie die Story-Leiste —, ein älterer allein als `SongDetailView`-Sheet. Eine Gruppe muss
dafür nicht erst gewählt werden: Der Chat macht seine beim Erscheinen schon zur
aktuellen, und die zeigen beide Feeds. Der Text der Nachricht fiel bei einer Erwähnung
bisher weg; jetzt steht er als Blase über der Karte, beide auf der Seite des Absenders.
Die Karte ist höchstens 280 Punkte breit — über die ganze Breite stand sie auf keiner
Seite. Was eine Nachricht zeigt, regelt `ChatMention.content` (vier Tests): leerer Text
fällt weg, und die Erwähnung eines Songs, der nicht mehr in der Gruppe ist, zeigt nur den
Text. VoiceOver liest die Karte als `Spoken.song` mit dem Hinweis „Öffnet den Song“.
Im Simulator belegt: alle drei Ziele, und die Eingabeleiste rückt weiter über den
Mini-Player. Gestern und älter nur mit einer vorübergehenden, nicht committeten Änderung:
Die Seed-Daten haben keine Erwähnung und keinen Song vor gestern, und der 🎵-Knopf bietet
nur heutige Songs an. Das VoiceOver-Label ist im Code gesetzt, im Simulator aber nicht
abgefragt — die Barrierefreiheits-Abfrage stand in der Sitzung nicht zur Verfügung.
Nebenbei gefunden: Der Commit, der die Erwähnung einführte (`e56bd71`), hatte beim
Einbau des Song-Pickers das Battle-Sheet entfernt — der „+“-Knopf im Chat öffnete seither
nichts, und die Erinnerung an alle war nicht mehr erreichbar. Das Sheet ist wieder da,
im Simulator geprüft, neben dem Picker.

## Regeln, die dieses Projekt sich gegeben hat

- **Keine Emoji auf Home** (ausdrücklicher Wunsch). SF Symbols stattdessen; die Streak
  trägt `todStreak`, das Notenzeichen `todAccent`. Gruppen-Emoji als Bild-Rückfall
  bleiben davon unberührt.
- Oberflächentexte **auf Deutsch**, informelles „du", keine Ausrufezeichen. Kommentare im
  Code auf Englisch. Das Bundle deklariert `CFBundleLocalizations: [de]` — ohne das
  kamen Systemtexte (relative Zeitangaben, Dialogknöpfe) auf Englisch zurück.
- Keine View verzweigt nach Dienstnamen — nur nach `MusicProviderCapabilities`.
- Reine Rechenregeln leben ohne SwiftUI und werden dort getestet: `TrackSection`,
  `Streak`, `GroupsFeed`, `RoundVisibility`, `SeasonScore`, `GroupPermissions`,
  `CommentTime`, `Waveform`, `Member.hasPosted`, `EmbedPlayGate`, `SectionStart`,
  `DailyReminders`, `CatalogMatch`, `ChatMention`.
- **Was sich aus Daten ableiten lässt, wird abgeleitet — nicht daneben gespeichert.**
  Zweimal hat in einer Nacht ein gespeicherter Wert über Mitternacht gelogen: Seed-Zeiten
  als „vor N Stunden" und `Member.hasPostedToday` als Flag, das beim Posten gesetzt und
  nie wieder gelöscht wurde. Beide hängen jetzt am Kalendertag bzw. an `postedDates`,
  so wie `currentStreak` es von Anfang an tat.
- **Der Glanz bleibt sparsam.** Genau zwei Stellen tragen einen Verlauf statt einer
  flachen Farbe: die Streak-Zahl und der Tabellenkopf. Mehr, und er hört auf, etwas
  zu bedeuten.
- Geteilte Test-Helfer gehören in `TodAppTests/TestSupport.swift`.
- Nach jeder neuen Datei `xcodegen generate` **und** die erzeugte `project.pbxproj`
  mitcommitten. Der Fehler lautet sonst „Typ nicht gefunden", obwohl die Datei
  danebenliegt.
- Ein Test, der nicht scheitern kann, wird gelöscht statt aufgepolstert.
- **Kein Knopf ohne Wirkung.** „Battle starten" und „Vote abschicken" sind beide
  verschwunden, weil sie nichts taten bzw. nichts mehr tun sollten. Ein Knopf, der
  einen Tipp schluckt, lehrt Leute, dass die App kaputt ist.

## Fallen, die heute Zeit gekostet haben

- **`Comment` ist zweideutig.** Swift Testing hat einen eigenen `Comment`, und
  `TodApp.Comment` löst nicht auf, weil das App-Struct auch `TodApp` heißt. In Tests
  keine `[Comment]`-Annotation schreiben — über die `Submission` gehen.
- **`Date.RelativeFormatStyle` ignoriert ein übergebenes `now`** und misst immer gegen
  die echte Uhr. `RelativeDateTimeFormatter` nimmt ein Bezugsdatum — nur damit ist die
  Regel testbar. Siehe `CommentTime`.
- **Der Testlauf installiert die App neu** und beendet dabei die laufende Instanz im
  Simulator. Danach landen Tipps auf dem iOS-Home-Bildschirm. Nach `xcodebuild test`
  immer neu starten.
- **Zeit im Seed gehört an den Kalendertag, nicht an „vor N Stunden".** Die Songs von
  heute standen als `Date().addingTimeInterval(-5400)` im Seed. Um 01:00 ist das der
  Vortag, also rutschten sie in die aufgedeckte Runde: `castVote` antwortete
  `.roundClosed` auf einen Song, den der Voten-Bildschirm noch anbot. Zwei Tests haben
  es gefangen — beim ersten Lauf dieser Suite nach Mitternacht überhaupt.
- **Tests nicht durch ein `grep` hindurch an einen Push hängen.** `xcodebuild test |
  grep ... && git push` pusht auch bei roten Tests, weil das `grep` erfolgreich ist.
  Genau so ging ein roter Stand raus.
- **Erst messen, dann bauen.** Die Play-Sperre wurde auf eine Zeitannahme gebaut —
  „der Druck kam vor Spotifys `ready`" —, die zum Log passte. Die Messung danach,
  0,78 s bis `ready`, hat sie widerlegt. Bei Zeitfragen zuerst die Latenz messen: eine
  Erklärung, die zum Log passt, ist noch keine Ursache.
- **Der Simulator zeigt keine Bildschirmtastatur**, solange die Mac-Tastatur als
  Hardware-Tastatur verbunden ist. Ob ein Feld den Fokus hat, verrät dann nur ein
  getippter Buchstabe — kommt er an oder nicht. Ein fehlender Cursor allein kann
  auch die Blinkpause sein. Wo es um das Layout mit Tastatur geht:
  `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`,
  Simulator-App neu starten, danach `defaults delete …` wieder. Getippter Text
  (`simctl`/Werkzeug) schaltet die Hardware-Tastatur wieder zu.
- **Manche Warnungen zeigt nur ein kompletter Neubau.** Zwei `PhotosPicker`-
  Beschriftungen griffen aus einem Sendable-Closure in den Store; aufgefallen ist es
  erst, als `xcodegen` alles neu bauen ließ.
- **Die Gemini-CLI ist für private Konten abgeschaltet**, seit dem 18. Juni 2026. Die
  Meldung „no longer supported for Gemini Code Assist for individuals“ ist die
  Abschaltung selbst; Update oder Neuinstallation helfen nicht. Ersatz ist die
  Antigravity CLI `agy` (`~/.local/bin/agy`), angemeldet und ohne Dialog nutzbar
  (`agy -p`). Den Diff in den Auftrag einbetten, dann braucht der Prüfer keine
  Werkzeuge.
- **Review-Befunde immer am Code prüfen.** Von 15 Befunden der `agy`-Prüfung waren
  8 falsch, einer davon frei erfunden. Der Prüfer sieht nur den Diff; was um die
  geänderten Zeilen herum steht, rät er.
- **Einen Seiten-Feed (`.scrollTargetBehavior(.paging)`) nicht zu einer späteren Karte
  scrollen.** Dreimal gemessen: Eine gebundene Scrollposition — als Anfangswert oder beim
  Erscheinen gesetzt — legte die Karte um die Höhe von Status- und Navigationsleiste zu
  hoch, unter die Leiste, und ließ unten die nächste hereinschauen; `scrollTo` beim
  Erscheinen scrollte gar nicht. Die erste Karte sitzt immer richtig — also rückt die
  gewünschte Karte nach vorn.
- **`log show` verschweigt `.info`.** Ohne `--info` bleibt die Spur leer, obwohl
  die App schreibt — die Erinnerungen loggen auf dieser Stufe.
- **Farbeindrücke messen, nicht schätzen.** Ein violetter Schimmer um eine Karte sah
  nach ausgelaufenem Schein aus; die Pixel außerhalb der Karte waren mit und ohne
  Song-Karte identisch. Es waren die Glasflächen selbst. Zwei „Korrekturen" gingen
  dafür drauf, bevor gemessen wurde.

## Was der Nutzer selbst tun muss

**Sobald der Developer-Account freigeschaltet ist, drei Schritte für Apple Music:**
1. **Team-ID in `project.yml` eintragen**, unter `targets → TodApp → settings → base`
   als `DEVELOPMENT_TEAM: <Team-ID>` — nicht in Xcode, das Projekt wird erzeugt und
   überschreibt es. Die Team-ID steht auf developer.apple.com unter „Membership“.
2. **MusicKit für die App einschalten:** developer.apple.com → Certificates,
   Identifiers & Profiles → Identifiers → `com.lennetschierhorn.TodApp` (anlegen, falls
   er fehlt) → Reiter „App Services“ → MusicKit anhaken → speichern.
3. **Auf einem echten iPhone mit Apple-Music-Abo** die App starten und im Profil „Mit
   Apple Music verbinden“ tippen. Danach prüft das Protokoll, ob Suche und Wiedergabe
   laufen.

**Das alte Spotify-Client-Secret im Dashboard widerrufen.** Es war nie committet
(`Secrets.xcconfig` stand von Anfang an in `.gitignore`), lag aber auf dem Rechner und
in jedem Build bis zum Umbau. Seit der Proxy weg ist, benutzt es nichts mehr.

Fürs Bauen auf dem eigenen iPhone: Apple-ID unter `Xcode → Settings → Accounts`, dann
Team in `project.yml` eintragen (nicht in Xcode — das Projekt wird generiert und
überschreibt es).

**Token-Tausch durchgesehen, zwei Fehler behoben.** Kein Secret geht raus, das
stimmt — die Anfragen tragen nur `client_id` und den PKCE-Verifier, und Tests halten
das fest. Zwei andere Dinge waren falsch:
- **Ein Netzfehler beim Start löschte die Anmeldung.** `restore()` warf den
  gespeicherten Token bei *jedem* Fehlschlag weg. Ein Start ohne Netz meldete damit ab,
  und der nächste Start hatte nichts mehr wiederherzustellen. Jetzt löscht nur eine
  echte Absage von Spotify (400, 401, 403); 429 und 5xx lassen den Token stehen.
  Dasselbe beim Auffrischen mitten in der Sitzung: der Fehler wird durchgereicht,
  statt jede Störung als „melde dich neu an“ auszugeben.
- **Der Anfragekörper war als Adresszeile kodiert.** `URLComponents` lässt `+`, `&`
  und `=` unangetastet, weil sie in einer Adresszeile erlaubt sind. In Formulardaten
  heißt `+` aber Leerzeichen, und ein `&` zerreißt den Körper in Felder, die niemand
  gesendet hat. Jetzt wird von Hand kodiert.

**Barrierefreiheit.** Vorher gab es acht Beschriftungen in der ganzen App. Jetzt: Die Wellenform ist **ein** Element statt vierzig namenloser Balken —
mit der Wiedergabeposition als Wert und Wischen hoch/runter in Fünf-Sekunden-Schritten,
denn eine Ziehgeste allein gibt es für VoiceOver nicht. Das Cover einer Songkarte ist
ein echter Knopf mit Namen statt einer Tipp-Geste auf einem Bild, Titel und Künstler
werden als ein Satz gelesen, eine getroffene Bewertung meldet sich als ausgewählt
(vorher nur eine Farbe), und die Story-Kreise sagen, ob jemand heute schon gepostet hat
— der Ring allein sagt das nur dem Auge. Gruppenzeilen kommen als ein Satz statt als
drei Bruchstücke. Die Sprachregeln liegen in `Spoken` und sind ohne SwiftUI getestet.
Die Schriftgrößen waren schon in Ordnung: die Tokens tragen `relativeTo:` und wachsen
mit der Systemschrift; die zehn festen Größen sind Symbole und Emoji, kein Text.

In einem zweiten Durchgang kamen die übrigen Bildschirme dazu: eine Ranglistenzeile ist
ein Satz samt „führt“ statt einer Krone, die sonst niemand hört; die Rundenkarten im
Chat, die Saisonzeilen und die Streak-Karte werden als je ein Satz gelesen; „💎 3“ heißt
jetzt „3 Hidden Gems“ statt „Edelstein 3“; sechs schmückende Symbole (Flamme, Note,
Lupe, Krone, Schloss, Karten-Icon) und das Gruppen-Emoji sind für VoiceOver
ausgeblendet, weil der Text daneben die Bedeutung schon trägt. Die Mini-Player-Leiste
hat einen echten Knopf bekommen: vorher öffnete eine Tipp-Geste den Song, die es für
VoiceOver nicht gibt, und der Pause-Knopf daneben bleibt eigenständig.

Ein dritter Durchgang nahm sich die letzten Bildschirme vor. Der **Abschnitt-Picker**
war die größte Lücke: zwei Ziehgriffe und ein Ziehfenster, alles nur mit den Fingern
zu bewegen. Start und Ende sind jetzt je ein eigenes Element mit ihrer Zeit als Wert
und Fünf-Sekunden-Schritten beim Wischen, die Balken sind ausgeblendet, und Start,
Länge und Ende werden als ein Satz gelesen. Eine Zeile in der Trefferliste beim Posten
heißt „Titel von Künstler“ statt Cover, Titel und Künstler nacheinander; eine
Battle-Karte nennt Name und Anteil in einem; ein Kommentar ist „Wer, wann, was“, ohne
die Initialen aus dem Avatar. Die Anmeldung brauchte nichts — ihr einziger Knopf trug
schon „bald verfügbar“. Zuletzt das Profil: Der Kopf jeder Karte wird als ein Satz
gelesen („Spotify · Suchen und Posten, Nicht verbunden“), und der große Kreis mit
Bild oder Initialen ist ausgeblendet, weil Namensfeld und „Bild wählen“ direkt
darunter stehen. Damit ist kein Bildschirm mehr unangetastet.

## Ungeprüft geblieben

- **Unabhängig geprüft am 14. September**, mit der Antigravity CLI (`agy`, Gemini
  3.1 Pro): alle 13 Commits von `497013b` bis `50bf451`, in zwei Teilen. Von 15
  Befunden hielten 5 der Prüfung am Code stand und sind behoben: Einen Song zu
  öffnen brachte den laufenden zum Schweigen (samt Mini-Player), der Katalog-Cache
  überging eine gespeicherte Apple-ID, die feat.-Regel ließ von „Featuring You“
  nichts übrig, die Formularkodierung ließ Nicht-ASCII-Buchstaben durch, und der
  Vorschau-Player hörte auf das Ende jedes beliebigen Items. Zwei weitere sind echt,
  bleiben aber: `replaceAll` löscht vor dem Neuanlegen (der nächste Start plant die
  Woche neu), und ein mitten in der Sitzung widerrufener Token meldet nicht ab
  (war schon vorher so; der nächste Start räumt ihn weg). Acht waren falsch, darunter
  ein Löschknopf, den es in der App nicht gibt, und ein angeblich nicht an den Main
  Actor gebundener `AppStore`. Ob Tipp-Erkenner Knopf-Hervorhebungen verzögern,
  blieb Vermutung; im Simulator reagierten die Knöpfe sofort. Die Player-Korrektur ist im
  Simulator belegt: Passionfruit lief volle 30 s weiter, während Sunflower geöffnet
  wurde — kein `load` für Sunflower bis zum Tipp auf Play —, und dieser Tipp lud und
  startete die Vorschau binnen 3 ms.
- Der Token-Tausch (`SpotifyTokenExchange`) ist durchgesehen und seit dem 14. September
  auch unabhängig geprüft (siehe unten).
- Der Fix für eine fehlgeschlagene Anmelde-Präsentation (`session.start()` liefert
  `false`) ist nur durch Lesen belegt.
- `KeychainTokenStore` hat keine direkten Tests; das Testziel hat keine Entitlements.
- **Die Mini-Player-Leiste ist gelesen, nicht gesehen.** Ihr Umbau zum echten Knopf
  ist nur im Code geprüft: Die Leiste zeigt sich ausschließlich während der Wiedergabe,
  und eine Apple-Vorschau dauert 30 Sekunden — kürzer, als ein Durchgang aus Tippen,
  Blatt wegschieben und Screenshot braucht. Zweimal war sie beim Auslösen gerade
  ausgelaufen. Wer die App ohnehin offen hat: Song öffnen, Play, Blatt wegschieben,
  hinsehen.
- **VoiceOver selbst ist nie gelaufen.** Die Beschriftungen sind gelesen und ihre
  Textregeln getestet, aber niemand hat die App mit eingeschaltetem VoiceOver bedient —
  besonders die Wellenform mit ihren Fünf-Sekunden-Schritten sollte jemand einmal
  wirklich hören. Unangetastet ist jetzt kein Bildschirm mehr; was fehlt, ist die Probe mit
  eingeschaltetem VoiceOver.
- Ein **sehr schneller Wisch** im Swipe-Feed hat einmal die Navigation zurückgeschoben
  statt zu blättern. Bei normalem Tempo blättert es zuverlässig, und es ließ sich nicht
  wieder auslösen.
