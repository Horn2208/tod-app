---
tags: [todapp, entscheidungen, musik-integration]
---

# Entscheidungen: Musik-Integration

Verwandt: [[2026-08-29-tod-app-music-embeds-design|Design-Spec]] · [[2026-08-29-music-embeds|Implementierungsplan]] · [[TodApp|Übersicht]]

Dieses Dokument hält fest, **welche Entscheidungen während der Umsetzung getroffen
wurden und warum** — besonders die, die vom ursprünglichen Plan abweichen. Der
Arbeitsverlauf selbst lag in `.superpowers/sdd/2026-08-29-music-embeds/`, einem
nicht versionierten Verzeichnis, das nach Abschluss gelöscht wird. Was hier steht,
bleibt.

Auffällig ist das Muster: Fast jeder Befund stammte aus dem **Plantext**, nicht aus
der Umsetzung. Die Prüfschleife hat also genau das gefunden, wofür sie da ist.

## Externe Randbedingungen (geprüft am 29.08.2026)

Zwei Eigenschaften fremder Dienste prägen den gesamten Entwurf. Sie können sich
ändern — wenn das Design in einem Jahr seltsam wirkt, steht hier der Grund.

**SoundCloud vergibt keine API-Zugänge mehr auf Zuruf.** Zugang läuft nur über ein
manuell geprüftes Formular mit Wochen Wartezeit und ungewissem Ausgang. Deshalb gibt
es dort keine In-App-Suche, sondern nur Link-Import über den öffentlichen
oEmbed-Endpunkt.

**Spotify liefert neuen Apps seit dem 27.11.2024 kein `preview_url` mehr.** Die
30-Sekunden-Vorschau kommt deshalb aus dem Embed-Player, nicht aus der Such-API.

## Sicherheitsrelevante Fehler, die die Prüfung gefunden hat

**Fremde Hosts wurden akzeptiert.** Die Host-Prüfung für SoundCloud-Links nutzte
`hasSuffix("soundcloud.com")` — ohne Punktgrenze. Damit wäre `evilsoundcloud.com`
als gültiger SoundCloud-Track durchgegangen. Jetzt wird nur der exakte Host und
echte Subdomains akzeptiert.

**Ein Absturz statt einer Ablehnung.** Der Spotify-Zweig des Link-Parsers baute die
URL per String-Interpolation aus `URLComponents.path` — und der ist bereits
percent-*dekodiert*. Bei `…/track/abc%20def` entstand ein String mit echtem
Leerzeichen, `URL(string:)` lieferte `nil`, und das Force-Unwrap ließ die App
abstürzen. Ausgerechnet der Parser, der schlechte Eingaben abfangen soll, wäre daran
zerbrochen.

**Stille URL-Korruption.** Der Embed-URL-Bau interpolierte die Track-ID roh in die
URL. Eine ID mit `?` oder `#` verschluckte den `theme=0`-Parameter — der Nutzer sähe
einen hellen Player im dunklen Design, ohne Fehlermeldung. Jetzt über
`URLComponents` mit percent-kodiertem Pfadsegment.

## Fehlermeldungen, die in die Irre geführt hätten

**401 als „Track nicht verfügbar".** Die Suche bildete jede Nicht-200-Antwort außer
429 auf `.trackUnavailable` ab. Ein abgelehntes Token — also fehlende oder falsche
Zugangsdaten — hätte damit als Problem *des Tracks* ausgesehen. Das ist genau der
erste Start, solange `Secrets.xcconfig` noch Platzhalter enthält. Jetzt gehen
401/403 auf `.missingSpotifyCredentials`, dessen Meldung die Datei beim Namen nennt.

**429 verschluckt.** Dasselbe auf der SoundCloud-Seite: Ein Rate-Limit erschien als
„privat oder gelöscht". Jetzt konsistent zur Spotify-Seite als `.rateLimited` mit
eigener Meldung.

## Architektur-Entscheidungen

**`TodAppError.network` gilt nie als gleich.** Der handgeschriebene
Gleichheitsvergleich verglich den umschlossenen Fehler über die Brücke nach
`NSError` — und die leitet den Code aus der *Position* des Enum-Falls ab, nicht aus
den Werten. Zwei völlig verschiedene Fehler galten damit als gleich. Da `AppStore`
jeden unbehandelten Fehler in diesen Fall wickelt, hätte ein Test grün gemeldet,
während in Wahrheit etwas anderes schiefging. Entscheidung: lieber zugeben, dass
Gleichheit nicht feststellbar ist. Ein Test dazu hält das absichtlich fest.

**Der Token-Cache teilt wirklich ein Token.** Zwei gleichzeitige Aufrufe konnten bei
leerem Cache beide an der Prüfung vorbeirutschen und je ein eigenes Token holen —
der Actor tat also nicht das, wofür er existiert. Der Prüfer hielt das für
vertretbar; die Entscheidung fiel dagegen, weil der kalte Cache der wahrscheinlichste
Fall ist (App öffnen, sofort tippen). Gelöst über eine festgehaltene laufende
Anfrage, die auf Erfolg *und* Fehler wieder freigegeben wird.

**Die Abbruch-Logik der Suche war toter Code.** Der Plan sah ein Feld vor, das
abgebrochen, aber nie zugewiesen wurde. Die Entprellung hätte nie eine laufende
Suche gestoppt, und ein langsames altes Ergebnis hätte ein neueres überschreiben
können. Ein Test mit anhaltbarem Mock hält das jetzt fest.

**Suchzustand gehört nicht in den `AppStore`.** Er ist nach dem Schließen des Sheets
Müll, und im Store würde jede andere View ihn mitbeobachten. Bewusste Abweichung von
der Architektur-Spec, die einen einzigen Store vorsieht.

**Spotify-Links lösen jetzt Metadaten auf.** Vorher zeigte der Bestätigungsdialog
die nackte URL, wo der Songtitel hingehört, und gar keinen Artist. Gelöst über
Spotifys **öffentlichen** oEmbed-Endpunkt — ohne Anmeldung, ohne Client-Credentials,
in derselben Bauform wie der SoundCloud-Client. Schlägt die Auflösung fehl, bleibt
der Post trotzdem möglich; nur der Titel bleibt karg, und eine Meldung erklärt warum.

## Zurückgezogene Anweisungen

**`deinit { searchTask?.cancel() }` geht nicht.** In Swift 6 ist `deinit` nicht
Main-Actor-isoliert und darf dessen isolierte Eigenschaften nicht anfassen. Der
Compiler lehnte es ab. Kein Workaround eingebaut — für ein Modell, das mit dem Sheet
stirbt und dessen Aufgabe sich selbst beendet, wäre das Aufwand ohne Gegenwert.

**`INFOPLIST_KEY_*` erreicht die Info.plist nicht.** Der geplante Weg, die
Zugangsdaten über Build-Settings einzuschleusen, funktioniert nicht — die Schlüssel
landen nachweislich nie in der gebauten Info.plist. Stattdessen eine explizite
`TodApp/Info.plist` über XcodeGen. Nebenwirkung: Die Datei wird von Hand gepflegt,
ein von Apple sonst automatisch gesetzter Schlüssel (`LSRequiresIPhoneOS`) fiel weg
und musste zurückgeholt werden.

## Offene Punkte

Task 8, 9 und 10 sind alle committet, getestet und final geprüft.

- **Verteilung ist gesperrt**, solange das Spotify-Secret in der App liegt: Aus einer
  IPA lässt es sich extrahieren. Vor TestFlight oder App Store muss der Proxy kommen,
  der in der [[2026-08-29-tod-app-music-embeds-design#Migration zum Proxy|Spec]]
  beschrieben ist, und das Secret dabei rotiert werden. (Ein Release-Build zieht
  `configFiles` inzwischen auf `Secrets.example.xcconfig`, damit ein Archive
  wenigstens nicht mehr *stillschweigend* ein Secret mitausliefert — das ersetzt
  den Proxy nicht, sondern verhindert nur den unbemerkten Fall.)
- **Voting zeigt weiterhin Farbflächen statt Artwork.** `VotingView`, `RevealView`
  und `BattleView` füllen ihre Karten noch aus `coverColorHex`; `TrackSource.artworkURL`
  wird dort nicht konsumiert.
- **Trefferzeilen der Suche zeigen kein Artwork.** `PostSongView`s Ergebnisliste
  rendert für jeden Treffer nur ein leeres graues Rechteck statt
  `candidate.source.artworkURL`.
- **`TrackEmbedView` hat keinen Rückfall bei Ladefehlern.** Der `WKWebView`-Wrapper
  hat keinen Navigation-Delegate; schlägt der Embed fehl (Netz, Dienst down), bleibt
  einfach eine leere/weiße Fläche stehen statt des in der Spec vorgesehenen
  Artwork-plus-„In Spotify öffnen"-Rückfalls.
- **Barrierefreiheit ist an keiner Stelle der App adressiert.** Kein
  `accessibilityLabel` o.ä. in der gesamten Codebase — betrifft insbesondere
  `TrackEmbedView` (ein natives `WKWebView`, für VoiceOver eine Black Box ohne
  Beschriftung) und die farbigen Platzhalter-Kacheln in Voting/Suche.
- Kleinere zurückgestellte Punkte: die ID-Prüfung akzeptiert Unicode-Buchstaben statt
  strikt Base-62; die Info.plist hat Versionsnummern als Literale statt als
  Build-Variablen.
