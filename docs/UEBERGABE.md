---
tags: [todapp, übergabe]
---

# Übergabe — Stand 11. September 2026, mittags

Alles committet und gepusht. Branch `feat/music-embeds`, **345 Tests grün**, keine
Build-Warnungen. Offener PR:
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
meldet sich im Profil unter „Spotify · Ganze Songs im Player“ selbst an; danach
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
  `DailyReminders`, `CatalogMatch`.
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
  auch die Blinkpause sein.
- **Manche Warnungen zeigt nur ein kompletter Neubau.** Zwei `PhotosPicker`-
  Beschriftungen griffen aus einem Sendable-Closure in den Store; aufgefallen ist es
  erst, als `xcodegen` alles neu bauen ließ.
- **`log show` verschweigt `.info`.** Ohne `--info` bleibt die Spur leer, obwohl
  die App schreibt — die Erinnerungen loggen auf dieser Stufe.
- **Farbeindrücke messen, nicht schätzen.** Ein violetter Schimmer um eine Karte sah
  nach ausgelaufenem Schein aus; die Pixel außerhalb der Karte waren mit und ohne
  Song-Karte identisch. Es waren die Glasflächen selbst. Zwei „Korrekturen" gingen
  dafür drauf, bevor gemessen wurde.

## Was der Nutzer selbst tun muss

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

- **Die Commits vom 11. September abends haben kein unabhängiges Review** —
  `497013b` (Erinnerungen, Tastatur), `453c540`, `fac419a` und der Nachschliff danach.
  Codex lief ins Nutzungslimit (wieder ab 27. September 2026, 15:25), Gemini lehnte die
  Anmeldung ab: der Zugang „Gemini Code Assist for individuals“ wird von dieser CLI
  nicht mehr unterstützt, Google verweist auf Antigravity. Beide hinterließen keine
  Änderungen. Durchgesehen habe nur ich selbst.
- Der Token-Tausch (`SpotifyTokenExchange`) ist inzwischen durchgesehen (siehe oben),
  aber wie alles seit dem 11. September nur von mir, nicht unabhängig.
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
