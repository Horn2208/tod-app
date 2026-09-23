---
tags: [todapp, übergabe]
---

# Übergabe — Stand 18. September 2026

Committet. Branch `feat/music-embeds`, **582 Tests grün**, keine Build-Warnungen. Nicht
committet und bewusst liegen gelassen: die iTunes-Rückfallsuche aus der Sitzung vom
14. September (vorgemerkt in `SpotifyProvider`, `MusicKitCatalog`, siehe „Konto mit Sign in
with Apple“), das Layout-Konzept im Prompt-Dokument und `.obsidian/graph.json`. Offener PR:
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

**Spotify spielt im Player abgemeldet** (`cc6fecf`, 23. September). Beim Testen mit
Freunden spielte Spotify auf dem iPhone des Nutzers (Premium, angemeldet) nichts,
auch Leos „Azzlack Versace“ nicht. Der Simulator ohne Anmeldung spielte die
30-Sekunden-Vorschau. Angenommene Ursache: Mit Premium versucht das Embed den ganzen
Song, und der braucht Kopierschutz, den die Web-Ansicht einer App auf dem iPhone
nicht bietet. Das Protokoll vom Gerät fehlt noch, bewiesen ist das also nicht. Der Umbau:
Das Embed läuft auf einem eigenen, nicht dauerhaften Speicher
(`SpotifyEmbedPlayer.makeConfiguration`) und sieht die Spotify-Anmeldung nie. Die
Anmeldung zieht das Embed auch nicht mehr vor einen Apple-Treffer. Ganze Songs kommen
nur noch von Apple Music (mit Abo) oder über „Spotify öffnen“. Im Simulator belegt:
Leos Song per Link spielt die Vorschau (29,78 s). **Auf dem iPhone noch zu prüfen.**
Danach gebaut, 23./24. September:
- **Link-Posts** holen Künstler und Länge von Spotifys öffentlicher Track-Seite
  (`SpotifyTrackPage`, `b848bba`, `50ee50a`). Im Simulator zeigt Leos Link
  „Soufian, Haftbefehl“ und 4:00.
- **Posts speichern ihr eigenes Cover und die Länge** (`Submission.artworkURL`,
  `durationSeconds`, `coverURL`; `26c8924`). Die Spalte `duration_seconds` wird jetzt
  auch beschrieben.
- **Apple-Suche** (`464bf8e`, `24beeea`): Ohne Spotify-Verbindung sucht das Posten
  in Apples offenem iTunes-Katalog. Ein Treffer wird als Post ohne Service-Link
  gespeichert, mit Apple-ID, Cover in 600 px und Länge. Eine Migration war nicht
  nötig. Im Simulator geprüft: suchen, Vorschau spielen, posten, Cover auf Home.
  Offen: Die Treffer kommen in Apples eigener Reihenfolge, Coverversionen stehen oft
  vor dem Original.
- **Spotify lehnt ab → Apple sucht** (`80b1510`): Wer Spotify verbindet, aber nicht auf
  der 5-Personen-Liste steht, bekommt bei jeder Suche eine Absage; dann springt Apple ein.
- **„Ganz in Spotify ab 1:10“** (`a84434d`): Für verbundene Premium-Konten spielt Spotify
  Connect den ganzen Song ab dem Abschnitt in der Spotify-App des Hörers, ohne Stopp am
  Abschnittsende. Der Nutzer will das behalten, um später Spotifys Extended Quota
  zu beantragen (seit Mai 2025 nur für Organisationen ab 250.000 MAU). Auf dem iPhone
  bestätigt: Spotifys Embed spielt abgemeldet die Vorschau (Protokoll 24. September).
  Der Connect-Knopf ist auf dem Gerät noch nicht angetippt.

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

**Play-Knopf auf der Feed-Karte, Prompt-Punkt 3i.** Unten rechts am Cover jeder Karte
im Bewertungs-Feed sitzt ein runder Play-/Pause-Knopf mit Fortschrittsring: reinhören
beim Durchwischen, ohne die Song-Ansicht zu öffnen (`QuickPlayButton`). Er nimmt
denselben Weg wie der Player in der Song-Ansicht (`TrackPlayerSheet.player`) und
dieselben app-weiten Player; was ein Druck auf Play tut — Post für den Mini-Player
merken, die anderen zwei Player anhalten, den richtigen umschalten —, steht jetzt
einmal in `PlayPress` und gilt für beide Knöpfe. So startet die Karte nie einen zweiten
Ton neben dem ersten, der Mini-Player zeigt, was sie spielt, und die Song-Ansicht findet
den Song schon laufend. Wo von der Karte aus nichts zu starten ist — SoundCloud spielt
nur im eigenen Widget, ein Song ohne Katalog-Treffer gar nicht —, gibt es keinen Knopf
(`QuickPlay.action`, getestet); solange der Katalog noch sucht, dreht er. Im Simulator
geprüft: Start, Wechsel auf die nächste Karte, Mini-Player folgt, Song-Ansicht zeigt
denselben Stand.

**Vorschau nach Fehlschlag wieder startbar.** Beim Ausprobieren riss im Simulator einmal
die Verbindung ab; die Vorschau stand danach auf „lädt gerade nicht“, und Play blieb
wirkungslos, bis ein anderer Song gewählt war — `PreviewPlayer.load` lud denselben Song
nie neu, und beide Knöpfe waren gesperrt. Jetzt lädt ein Druck auf Play einen
fehlgeschlagenen Song neu; gesperrt ist der Knopf nur noch, wenn Apple für den Song gar
keine Vorschau hat. Der Test dazu ist ohne die Änderung rot (geprüft).

**Eine Wellenform beim Posten, Prompt-Punkt 3i (zweiter Teil).** Beim Posten standen zwei
Wellenformen übereinander: die des Players (Fortschritt, Ziehen zum Spulen) und die der
Abschnittswahl (andere Balken, eigener Seed). Jetzt ist die Abschnittswahl die Wellenform
des Players (`TrackPlayerSheet(sectionEditing:)`): der ganze Song als eine Leiste, das
Fenster mit beiden Griffen darüber (VoiceOver weiter in Fünf-Sekunden-Schritten), und die
Balken sind die des Players (`Waveform`, gleicher Seed) — der Song sieht beim Posten so aus
wie später für alle, die ihn hören. `WaveformShape` ist mit seinen Tests weg.
Wo die Wiedergabe steht, zeichnet die Leiste nur, wenn ihr Platz im Song bekannt ist: bei
einem ganzen Song von Apple Music oder Spotify. Apples Vorschau ist ein fester 30-Sekunden-
Ausschnitt, den Apple nicht verortet, Spotifys Ausschnitt ebenso — dort läuft der
Fortschritt als Ring um den Play-Knopf (`TrackPlayerSheet.songPosition`, getestet; die
Rechnung der Leiste in `SectionTimeline`, getestet). Wird das Fenster verschoben, während
ein ganzer Song läuft, springt die Wiedergabe nach dem Loslassen an den neuen Start. Im
Simulator geprüft: eine Leiste, Vorschau mit Ring, Fenster ziehen. Die Linie auf der Leiste
für ganze Songs ist nur per Test belegt — im Simulator gibt es weder Abo noch Spotify-Login.

**Wer den gewählten Abschnitt hört, Prompt-Punkt 3i (17. September).** Ab dem gewählten
Punkt hört ein Song nur, wer ihn ganz bekommt: Spotify mit Premium in der App, Apple Music
mit Abo. Alle anderen hören die feste Kurz-Vorschau des Dienstes. Das steht jetzt an zwei
Stellen, ruhig und ohne Warnfarbe:
- **Beim Posten** unter Start/Länge/Ende ein fester Satz in `todTextFaint`, je nach Quelle
  (`SectionReach.note`, getestet): bei Spotify-Songs beide Wege, bei Songs ohne Link nur
  Apple Music, bei SoundCloud keiner — dessen Widget spielt für alle von vorn und sagt das
  schon selbst.
- **Auf der Feed-Karte** ein kleines „30s“ am Play-Knopf, wenn der Druck die Kurz-Vorschau
  spielt (`QuickPlay.playsPreview`, getestet): immer bei Apples Vorschau, nie beim ganzen
  Song; bei Spotifys Embed nach dem, was Spotify für diesen Song gemeldet hat, vorher nach
  der Anmeldung. VoiceOver sagt „kurze Vorschau“ dazu.
Im Simulator geprüft: „30s“ am Knopf, Satz unter der Abschnittswahl. Nebenbei: zweizeilige
Titel in der Trefferliste beim Posten standen mittig über einem linksbündigen Künstler;
jetzt linksbündig.

**Supabase eingebunden, Fahrplan-Phase 1 begonnen (17. September).** Das Projekt
`jawnyansvxsburutjxtv` ist angebunden, noch ohne Daten: Adresse und öffentlicher
Client-Schlüssel (der alte `anon`-Schlüssel) stehen in `Config/Secrets.xcconfig`, das git
ignoriert. `Config/TodApp.xcconfig` holt die Datei, wenn es sie gibt (`#include?`), und
schreibt die Werte beim Bauen in die Info.plist; eingecheckt sind dort nur die Namen
`$(SUPABASE_URL)`/`$(SUPABASE_ANON_KEY)`. `SupabaseConfig` liest sie (getestet: leer,
nicht ersetzt, nur eins von beiden oder `http` heißt „kein Backend“), und die App meldet
beim Start im Log (`backend`), mit welchem Projekt sie spricht — nur den Host. Geprüft:
Adresse und Schlüssel gehören zusammen (Auth-Einstellungen antworten mit 200, nur
E-Mail-Anmeldung ist an), die gebaute App trägt die Adresse, das Log nennt sie.
Auf einem anderen Rechner: `Config/Secrets.example.xcconfig` nach `Secrets.xcconfig`
kopieren und die Werte aus dem Dashboard eintragen (Project Settings → API Keys). Nie den
`service_role`-/Secret-Schlüssel — der Client-Schlüssel landet in der App, und was er darf,
entscheidet RLS auf dem Server. Supabase empfiehlt für neue Clients den
„publishable“-Schlüssel; der `anon`-Schlüssel geht weiter.

**Datenbank angelegt (17. September).** Über den Supabase-MCP-Server (für Claude Code nur
auf dieses Projekt beschränkt, lokal eingetragen, nicht im Repo) sind zwei Migrationen
eingespielt; dieselben Dateien liegen in `supabase/migrations/`, nach der Version benannt,
die Supabase verbucht hat:
- `initial_schema`: `profiles` (per Trigger bei der Registrierung), `groups`,
  `group_members`, `group_invites` mit `join_group(code)`, `submissions`, `votes`,
  `hidden_gems`, `comments`, `chat_messages`. Alles hinter RLS; `anon` darf nichts,
  `authenticated` nur die Spalten, die die App schreibt — Autor, Zeit und Runde setzt der
  Server. Die Runde eines Posts rechnet die Datenbank aus dem Zeitpunkt (Europe/Berlin),
  einer pro Person, Gruppe und Tag. Fremde Bewertungen und Hidden Gems sieht man erst am
  Tag danach; bewerten geht nur heute und nie den eigenen Song. Gruppenname und -bild
  dürfen alle Mitglieder ändern, wer einladen darf nur der Ersteller.
- `pictures_and_vote_key_index`: private Buckets `avatars/<user>/…` (sichtbar für Leute
  aus denselben Gruppen) und `group-images/<gruppe>/…` (für Mitglieder), je 5 MB, JPEG,
  PNG, HEIC; dazu ein Index, den der Performance-Berater verlangt hat.
Vor dem Einspielen lief jedes Stück einmal als Probelauf mit Testnutzern und Rollback: 30
Regeln fürs Schema, 9 für die Bilder, alle wie gewollt; danach war die Datenbank wieder
leer. Die Berater melden nur noch zweierlei, beides gewollt: `join_group` ist für
Angemeldete aufrufbar (dafür ist es da), und die Indizes sind in einer leeren Datenbank
noch unbenutzt. Löschen in `storage.objects` lässt Supabase nur über die Storage-API zu;
die Löschregeln sind deshalb nicht per SQL geprüft, gleichen aber den geprüften.
Noch offen in Phase 1: Live-Updates im Chat, die Battles, und in der App
`SupabaseRepository`.

**Konto mit Sign in with Apple (17. September).** Die Tür in die App ist jetzt ein Konto,
nicht mehr Spotify: `SignInView` zeigt „Mit Apple fortfahren“, und `AccountService`
(`SupabaseAccountService`, Supabase-Swift 2.55.2, fest gepinnt, `Package.resolved`
eingecheckt) tauscht Apples Identitäts-Token gegen eine Supabase-Sitzung
(`signInWithIdToken`, mit Nonce: der Hash geht an Apple, der Klartext an den Server —
`AppleSignIn`, getestet). Den Namen gibt Apple nur beim allerersten Anmelden; dann
überschreibt er den aus der E-Mail gebildeten Profilnamen (`AppleSignIn.displayName`:
Vorname, sonst Spitzname, sonst Nachname, höchstens 40 Zeichen). `AppStore.account` sagt,
ob jemand angemeldet ist; das Laden der Gruppen hängt daran. Abmelden (unten im Profil, mit
Rückfrage) meldet nur dieses iPhone ab und trennt Spotify gleich mit.
Spotify ist jetzt eine Verbindung im Profil („Spotify verbinden/trennen“,
`connectSpotify`/`disconnectSpotify`, `isSpotifyConnected`) — für Spotify-Suche und den
Spotify-Player. Die Suche läuft vorerst weiter nur über Spotify; ohne Verbindung sagt sie
das und zeigt aufs Profil. Eine Apple-Suche ist Prompt-Punkt 3g.
Ohne `Config/Secrets.xcconfig` und in den Tests gilt `LocalAccountService`: immer der
lokale Nutzer „du“, so läuft die App wie vorher auf den Daten im Speicher. Die Daten liegen
auch mit Konto noch im Speicher — `SupabaseRepository` ist der nächste Schritt.
Nicht übernommen aus der Sitzung vom 14. September (war vorgemerkt, nie committet):
„Ohne Musikdienst weiter“ ist mit dem Konto überflüssig; die iTunes-Rückfallsuche in
`SpotifyProvider` gab Apple-Treffer als Spotify-Songs aus (Spotify-Zeichen, Link und
gespeicherte Quelle falsch) und bleibt deshalb liegen, bis 3g es richtig macht.
Signierung und Berechtigung stehen jetzt in `project.yml` (`CODE_SIGN_STYLE: Automatic`,
`Apple Development`, `TodApp.entitlements` mit Sign in with Apple), damit `xcodegen` sie
nicht wieder löscht.
Im Simulator geprüft: Anmeldebildschirm, Apples Systemdialog erscheint — der Simulator
hat keinen Apple Account, also endet es dort mit einer ruhigen Fehlermeldung —, Profil mit
Spotify-Karte und Abmelde-Rückfrage. Ein echter Durchlauf geht nur auf dem iPhone und
braucht eine Einstellung (siehe „Was der Nutzer selbst tun muss“): im Supabase-Dashboard
unter Authentication → Sign In / Providers → Apple den Anbieter an und die Bundle-ID als
Client ID. „Sign in with Apple“ an der App-ID hat Xcode beim automatischen Signieren
selbst freigeschaltet. Am 18. September war der Anbieter in Supabase noch aus — das ist
der Grund, warum die Anmeldung auf dem iPhone scheitert.

**Die App an die Datenbank angeschlossen (17./18. September).** Mit Konto liegen Gruppen,
Mitglieder, Posts, Kommentare, Bewertungen, Hidden Gems, Chat, Profil und Bilder jetzt in
Supabase. Plan: `docs/superpowers/plans/2026-09-17-supabase-repository.md`.
- `SupabaseRepository` erfüllt dieselben Protokolle wie `InMemoryRepository` und bleibt
  dünn; `AppStore.live()` gibt ihm denselben Client wie `SupabaseAccountService`, also eine
  Sitzung für beides. Ohne `Config/Secrets.xcconfig`, in Tests und mit dem Debug-Schalter
  `-inMemoryData` bleibt alles im Speicher.
- Daneben die reinen, getesteten Teile: `BackendRecords` (Zeilen, jede uuid klein
  geschrieben), `GroupAssembly` (Zeilen → `Group`; Posting-Tage, Rundenende und
  Ersatzfarbe werden abgeleitet), `BackendPayloads` (nur die Spalten, die die App schreiben
  darf, auf die Längen der Datenbank gekürzt), `ScoreTally`, `RoundDay` (Berliner Tag wie
  die Datenbank), `BackendError` (was eine Absage bedeutet: RLS beim Bewerten heißt „Runde
  vorbei“, der Unique-Key beim Posten „heute schon gepostet“), `ImageDownscale` (Bilder
  höchstens 1024 px als JPEG).
- **Die Identität kommt aus dem Konto**, nicht mehr aus `"du"`: Stimmen, Posts, Einladungen
  und die Eigener-Song-Regel folgen der Konto-id, das Profil kommt aus
  `ProfileRepository`. Abmelden vergisst Profil, Stimmen, Punkte und Gruppenwahl.
- **Einladen heißt jetzt Code.** Hinter einem getippten Namen steht mit echten Konten
  niemand. In den Gruppeneinstellungen erzeugt „Einladungscode erstellen“ einen Code
  (7 Tage gültig) mit „Code teilen“; beigetreten wird unter Gruppen → „+“ → „Mit Code
  beitreten“ (`join_group`). Ein neues Konto sieht auf Home und Gruppen „Gruppe erstellen“
  und „Mit Code beitreten“ statt eines endlosen Ladekreises; ein gescheitertes Laden bietet
  „Nochmal versuchen“.
- **Fehler werden sichtbar:** ein Banner oben zeigt jeden neuen Fehler ein paar Sekunden
  (`ErrorBanner`, an `errorCount` statt am Fehler, weil `.network` sich selbst nie gleicht).
- **Speichern nur, was sich ändert, und nacheinander.** Namen (Profil, Gruppe) werden nach
  einer Tipp-Pause und beim Verlassen gespeichert; eine Änderung trägt nur ihr Feld, und sie
  vergleicht mit dem Stand nach der vorigen. Eine abgelehnte Profiländerung wird
  zurückgenommen. Bewerten ist „ändern, sonst anlegen“, kein Upsert (der würde Song und
  Tag mitschreiben, die nicht geändert werden dürfen).
- Neu geladen wird beim Zurückkommen in die App und per Herunterziehen (Home, Gruppen,
  Chat); der Chat öffnet bei der neuesten Nachricht. Live-Updates im Chat fehlen noch,
  Battles haben keine Tabelle (mit Datenbank gibt es kein laufendes Battle), Premium bleibt
  der lokale Schalter.
- Lange Listen kommen in Seiten zu 1000 Zeilen (Supabases Grenze), der Chat als die letzten
  200 Nachrichten je Gruppe.
**Geprüft:** alle Abfragen gegen das echte Schema — ohne Anmeldung lehnt der Server mit
„permission denied“ ab, prüft aber vorher Spalten und Verknüpfungen; eine absichtlich
falsche Spalte oder Verknüpfung gab dort einen anderen Fehler. Im Simulator auf den Daten im
Speicher: „+“-Menü, Gruppe anlegen, Einladungscode mit Ablaufdatum. Unabhängig geprüft mit
`agy` (Gemini 3.1 Pro): sechs Befunde, alle am Code bestätigt und behoben (`83645c5`) — der
wichtigste: eine Umbenennung schickte die alte Einlade-Einstellung mit und konnte eine
gerade geänderte zurückdrehen.
**Auf dem iPhone geprüft (18. September, iPhone 15 „Oki“, Debug-Build von `fdacb65`):** Der
Nutzer hat sich mit Apple angemeldet (der Anbieter ist seit dem 18. September in Supabase
an), Profilname und -bild geändert, eine Gruppe mit Bild angelegt, einen Einladungscode
erzeugt, einen Song gepostet, kommentiert und im Chat geschrieben; nach dem Wegwischen und
neu Öffnen war alles noch da (vom Nutzer bestätigt). In zwei Läufen kein einziger
gescheiterter Datenbankzugriff im Protokoll. **Noch offen:** Bewerten und Hidden Gems
zwischen zwei Personen, die Aufdeckung am Tag danach, die Zugriffsregeln mit einem zweiten
Konto. Dafür braucht es eine zweite Person mit Code — oder anonyme Anmeldungen im Projekt,
dann meldet sich ein Debug-Build mit `-anonymousSignIn` im Simulator ohne Apple an (siehe
„Was der Nutzer selbst tun muss“).
**Ganze Songs von Apple Music auf dem iPhone gehört**, zum ersten Mal auf einem Gerät: drei
Songs, jeweils ab dem gewählten Abschnitt (Protokoll `applemusic`: „play … from 48.0“,
„from 44.47“, „from 40.33“). Direkt nach der Installation scheiterte der erste Song dreimal
mit „Die Daten konnten nicht gelesen werden, da sie nicht das korrekte Format haben“, beim
vierten Druck lief er, nach einem Neustart der App sofort. Die Ursache ist offen; das
Protokoll schrieb nur Apples Satz und schreibt jetzt den ganzen Fehler
(`AppleMusicPlayer.fail`). Tritt es wieder auf, steht dort, welcher Schritt und welcher Typ.
**So liest man auf dem iPhone mit:** App bauen und installieren (`xcodebuild … -destination
'platform=iOS,name=Oki'`, `xcrun devicectl device install app`), dann starten mit
`xcrun devicectl device process launch --device <id> --terminate-existing --console
--environment-variables '{"OS_ACTIVITY_DT_MODE": "enable"}' com.lennetschierhorn.TodApp` —
die Umgebungsvariable spiegelt das `Logger`-Protokoll in die Konsole. Ein gescheiterter
Datenbankzugriff steht dort als `[backend] read/post/vote/join/write: …`.

**Drei Wege in die App (18. September).** Der Startbildschirm bietet „Mit Apple fortfahren“
(weiß, Apples Knopf), „Mit Spotify fortfahren“ (Spotify-Grün, schwarze Schrift) und „Ohne
Anmeldung weiter“ (unser Rosa) — alle drei als Pillen gleicher Höhe. Jeder Weg endet in
einem Konto, weil der Server ohne keins etwas herausgibt:
- **Spotify** meldet über Supabase an (`signInWithOAuth(.spotify)`, Rückkehr nach
  `todapp://auth/callback`) — im eigenen Web-View der App (`WebAuthentication`), damit die
  Spotify-Sitzung danach dem Player und der Musik-Verbindung gehört. Danach verbindet die App
  Spotify zum Abspielen (`connectSpotify`); das fragt höchstens noch nach Zustimmung, nicht
  nach dem Passwort. Wer diese zweite Seite schließt, ist trotzdem drin. Das Konto trägt den
  Spotify-Namen (der Trigger nimmt `name` aus den Metadaten).
- **Ohne Anmeldung** macht ein anonymes Supabase-Konto (`AccountUser.isAnonymous`). Es kann
  alles, lebt aber nur auf diesem iPhone: Abmelden oder die App löschen, und es ist weg. Das
  sagen der Satz unter den Knöpfen, eine Zeile im Profil und die Abmelde-Rückfrage.
- Geprüft: 589 Tests, der Bildschirm im Simulator, und „Ohne Anmeldung“ gegen das echte
  Projekt, solange anonyme Anmeldungen dort noch aus sind — ruhiger Hinweis „Die Anmeldung
  hat nicht geklappt“. Der Spotify-Weg braucht erst die Einrichtung unten.
- Später sinnvoll: ein Konto ohne Anmeldung nachträglich mit Apple oder Spotify sichern
  (Supabase kann Identitäten verknüpfen).

**Player-Vollansicht nach dem Referenzbild (18. September, Prompt-Dokument „Player-
Vollansicht: neues Referenzdesign“).** Die Song-Ansicht (`SongDetailView` mit
`TrackPlayerSheet`) sieht jetzt so aus: großes Cover mit Schatten (Apples 100-px-Cover wird
als 600 px angefragt, `ArtworkSize`), Titel fett und Künstler gedimmt darunter, die
Wellenform im Verlauf Rosa→Gold bis zur Wiedergabestelle mit weichem Übergang ins Grau
statt harter Kante (`WaveformFill`), die Zeit mittig, drei Knöpfe — 15 s zurück, Play groß
und rosa gefüllt, 15 s vor (`PlaybackSkip`) —, der Lautstärkeregler des iPhones
(`SystemVolumeSlider`, `MPVolumeView`; im Simulator unsichtbar, nur die Lautsprecher-Zeichen)
und Pillen „Music öffnen“ / „Spotify öffnen“ / „SoundCloud öffnen“ mit Umrandung statt Fläche
(`PlatformLinks`). Die Zeichen darin sind Platzhalter bis zu echten Marken-Assets (3h). Die
Kommentare standen schon im selben Bildschirm; ihre Überschrift ist jetzt eine. Der
Hintergrund ist die Farbe des Covers (`CoverTint`), wie das Dokument verlangt, nicht das
Pink des Referenzbilds. Beim Posten bleibt der Player kompakt (Abschnittswahl, kleiner
Knopf mit Ring). Im Simulator geprüft: Genesis (Apple-Vorschau) spielt, der Verlauf wandert
mit, „15 s vor“ springt von 0:13 auf 0:28; beim Posten Abschnittswahl und Spotify-Pille.
Auf dem iPhone ungesehen: der Lautstärkeregler.

**Für TestFlight vorbereitet (18. September, Fahrplan-Phase 3).** Was ein Upload braucht und
fehlte, ist da: ein **App-Icon** (`TodApp/Assets.xcassets/AppIcon.appiconset`, 1024 px, dunkler
Grund mit rosa Schimmer und einer Wellenform von Rosa nach Gold; neu zeichnen mit
`swift tools/make-app-icon.swift TodApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png`),
`ITSAppUsesNonExemptEncryption = false` (nur HTTPS, keine Exportfrage je Build), ein
**Datenschutz-Manifest** (`TodApp/PrivacyInfo.xcprivacy`: Name, E-Mail, Konto-id, Bilder und
Inhalte, alles ans Konto gebunden, nur für die App, kein Tracking; Gründe-APIs nutzt die App
keine), und die App ist **nur fürs iPhone** gebaut (`TARGETED_DEVICE_FAMILY: "1"`) — als
iPhone-und-iPad-App mit nur Hochformat hätte Apple den Upload abgelehnt. Ein Release-Archiv
baut lokal (`xcodebuild archive … -configuration Release -destination 'generic/platform=iOS'`)
und enthält Icon, Manifest, die Supabase-Adresse und keinen der Debug-Wege. **Hochgeladen
am 18. September, 21:50:** Version 1.0, Build 1, Stand `48967f4` (Archiv mit
`-allowProvisioningUpdates`, Export mit `method: app-store-connect`, `destination: upload`,
`manageAppVersionAndBuildNumber: false`) — „Upload succeeded“. Der nächste Upload braucht
Build 2 (`CURRENT_PROJECT_VERSION` in `project.yml`). Für den App Store später (Phase 4) fehlt
noch: Konto löschen in der App (Apple verlangt es für Apps mit Konten), eine
Datenschutzerklärung.

**Bewertungskarte nach dem Layout-Konzept (18. September, Prompt-Dokument „Bewertungs-
Ansicht“).** Im Bewertungs-Feed (`SongFeedView`) sind Bewertung, Hidden Gem und Begründung eine
Glaskarte: fünf gleich breite Felder statt kleiner Kapseln, jedes mindestens 44 pt hoch, das
gewählte rosa gefüllt und beim Antippen kurz kleiner (`PressScale`); darunter der Hidden Gem als
eigener Pillen-Schalter mit Edelstein (SF Symbol statt Emoji), gesetzt mit Gold-Verlauf gefüllt;
darunter das Begründungsfeld, das wie bisher die Leiste über der Tastatur öffnet
(`NoteComposer`). Im Simulator geprüft: „Banger“ tippen, Gem setzen, Zähler „1 von 4 bewertet“.

**Achtung, Repo in `~/Documents`.** Am 16. September um 22:38 hat etwas das Prompt-Dokument
mit einer Stunden alten Fassung überschrieben, zwei Sekunden vor einem Commit, der sie
mitnahm (`2a5bc07`, repariert in `91675cd`). Obsidian lief nicht; „Schreibtisch & Dokumente“
wird über iCloud abgeglichen, das ist die naheliegende Erklärung, aber nicht bewiesen.
Außerdem blieb eine leere `.git/index.lock` aus einer Sandbox über Nacht liegen. Vor einem
Commit lohnt ein Blick in `git diff` auf die Dateien, die man mitnimmt.

**Ein Remix ist nicht das Original.** Der Katalog-Abgleich warf jede Klammer- und
Strich-Notiz weg, also auch „(Remix)“, und ohne bekannte Länge gewann der erste Treffer. Die
iTunes-Suche nach „Blinding Lights The Weeknd“ listet das Remix mit ROSALÍA, das von Major
Lazer und die Instrumental-Fassung vor dem Album-Original — der Beispiel-Post spielte das
Remix. Jetzt bleibt eine Notiz, die eine andere Aufnahme benennt (Remix, Live, Acoustic,
Unplugged, Instrumental, Sped Up, Slowed, Karaoke, Cover, Demo, A cappella), mit ihren
Wörtern Teil des Titels (`CatalogMatch.normalized`): „(Remix)“ findet nur das
ROSALÍA-Remix, „- Major Lazer Remix“ nur das von Major Lazer, ein Titel ohne solche Notiz
keine Fassung mit ihr und umgekehrt. Credits in der Notiz („feat.“, „with“) und das Wort
„Version“ zählen nicht mit; Remaster, Radio Edit und Soundtrack-Zusätze fallen weiter weg,
dort entscheidet die Länge. Weil `CatalogKey` dieselbe Regel nutzt, teilen sich Original
und Live-Fassung ohne Link keinen Cache-Eintrag mehr. Zehn neue Tests an der echten
Trefferliste vom 16. September; sieben waren vor der Änderung rot, drei sichern ab, was nicht
kippen darf („Nights - Remastered“, „Live Forever“, „feat. Cover Drive“). Im Simulator lädt
der Beispiel-Post jetzt `1499386265` (Album „After Hours“) statt `1542842761` und spielt
die Vorschau bis zum Ende. **Grenzen:** „Mix“ steht absichtlich nicht auf der Liste
(„Original Mix“ ist das Original), eine „Extended Mix“ ohne bekannte Länge geht also noch als
Original durch. Schreiben die Dienste eine Fassung verschieden („Live“ gegen „Live at SoFi
Stadium“), gibt es keinen Treffer, und das Spotify-Embed spielt — lieber kein Apple-Player
als die falsche Aufnahme. **Falle beim Prüfen:** Auf einem frisch gebooteten Simulator
(iPhone 17 Pro Max) lief die iTunes-Suche in den 5-s-Timeout (`-1001`); dann nimmt die
Karte den Embed-Weg, der dort ebenfalls nicht lud. Das sah aus wie ein kaputter Abgleich,
war aber das Netz — im Log nach `NSURLErrorDomain` suchen, bevor man den Code verdächtigt.

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

- **Tests sehen eine alte App, obwohl die App neu baut.** Am 18. September meldeten die Tests
  „has no member“ für Funktionen, die im Code standen und die App kompilierte. Ursache: die
  Modul-Kopie unter `DerivedData/…/Build/Products/Debug-iphonesimulator/TodApp.swiftmodule`
  war von 17:13 und wurde nicht mehr überschrieben, die frische Fassung lag nur unter
  `Intermediates.noindex/…/Objects-normal/arm64/TodApp.swiftmodule`. Zeitstempel beider
  vergleichen; die alte Kopie löschen, der nächste Build legt sie neu an.

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

**Für TestFlight:**
1. App Store Connect → Apps → „+“ → Neue App: Plattform iOS, Name (muss im App Store
   einmalig sein; ist „TodApp“ vergeben, z. B. „TodApp – Track of the day“), Primärsprache
   Deutsch, Bundle-ID `com.lennetschierhorn.TodApp` auswählen, SKU frei wählbar (z. B.
   `todapp-001`).
2. Bescheid geben — dann wird ein Build archiviert und hochgeladen. Beim ersten Upload legt
   Xcode über die automatische Signierung ein Verteilungszertifikat an.
3. TestFlight → Testinformationen: Feedback-E-Mail und ein Satz, was getestet werden soll.
4. Eine externe Gruppe (z. B. „Freunde“) anlegen, den Build hinzufügen — der erste geht
   einmal durch Apples Beta-Review —, dann per E-Mail oder öffentlichem Link einladen. Interne
   Tester müssten Mitglieder des App-Store-Connect-Teams sein (höchstens 100); externe gehen bis
   10.000. Ein Build ist 90 Tage testbar; jeder neue Upload braucht eine höhere Build-Nummer
   (`CURRENT_PROJECT_VERSION` in `project.yml`).

**Für „Mit Spotify fortfahren“ (einmalig):**
1. Supabase-Dashboard → Authentication → Sign In / Providers → **Spotify**: einschalten,
   Client ID `4c30dc0c418b42dea36251087825c547` und das **Client Secret** der Spotify-App
   eintragen (liegt nur bei Supabase, nie in der App). Die dort angezeigte **Callback URL**
   kopieren.
2. Spotify Developer Dashboard → die App → Settings → **Redirect URIs**: diese Callback URL
   hinzufügen (`https://jawnyansvxsburutjxtv.supabase.co/auth/v1/callback`), speichern.
3. Supabase-Dashboard → Authentication → **URL Configuration** → Redirect URLs:
   `todapp://auth/callback` hinzufügen.
4. Solange die Spotify-App im Development Mode ist, kommen nur Leute hinein, die dort unter
   „User Management“ eingetragen sind (höchstens 25).

**Für „Ohne Anmeldung weiter“:** Authentication → Sign In / Providers → „Allow anonymous
sign-ins“ dauerhaft einschalten. Es bleibt an, weil der Knopf sonst nur einen Fehler zeigt.

**Für den Test gegen die echte Datenbank im Simulator:** Supabase-Dashboard →
Authentication → Sign In / Providers → „Allow anonymous sign-ins“ einschalten. Dann meldet
sich ein Debug-Build, gestartet mit `-anonymousSignIn`, ohne Apple an. Nach dem Test wieder
ausschalten: Solange es an ist, kann sich jeder mit dem öffentlichen Schlüssel ein Konto
machen (sehen kann so ein Konto nur Gruppen, in die es eingeladen wird).

**Für die Anmeldung mit Apple, eine Einstellung (kein Secret-Key nötig):**
Supabase-Dashboard → Authentication → Sign In / Providers → Apple: einschalten und unter
„Client IDs“ `com.lennetschierhorn.TodApp` eintragen. Den OAuth-Teil (Services ID,
Schlüssel) braucht nur eine Web-Anmeldung, die App nicht. Auf developer.apple.com ist
nichts zu tun: Die App wird automatisch signiert, Xcode verwaltet die App-ID und hat
„Sign in with Apple“ aus den Entitlements selbst freigeschaltet — das Profil vom
17. September trägt `com.apple.developer.applesignin` (nachzulesen mit
`security cms -D -i <profil>.mobileprovision` unter
`~/Library/Developer/Xcode/UserData/Provisioning Profiles`). Anhaken lässt sich dort
nichts.
Danach auf dem iPhone mit „Mit Apple fortfahren“ anmelden; im Supabase-Dashboard unter
Authentication → Users erscheint das Konto, unter Table Editor → profiles das Profil.

**Für Apple Music, zwei Schritte** (die Team-ID steht schon in `project.yml`):
1. **MusicKit für die App einschalten:** developer.apple.com → Certificates,
   Identifiers & Profiles → Identifiers → `com.lennetschierhorn.TodApp` → Reiter „App
   Services“ → MusicKit. MusicKit ist keine Berechtigung im Profil, ob es an ist, lässt
   sich also nicht dort nachlesen; lässt die Seite nichts anhaken, ist es vermutlich wie
   bei Sign in with Apple schon verwaltet — Schritt 2 zeigt es.
2. **Auf einem echten iPhone mit Apple-Music-Abo** die App starten und im Profil „Mit
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
