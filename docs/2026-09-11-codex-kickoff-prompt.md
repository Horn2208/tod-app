# Kickoff-Prompt für codex-cli: TodApp-Redesign umsetzen

Kopier das hier komplett in codex-cli (oder gemini-cli), im Projektordner
`~/Documents/claude projekte/tod-app/` gestartet.

---

## Auftrag

Du arbeitest am Xcode-Projekt **TodApp** in diesem Repo. Die komplette
Spezifikation für das aktuelle Redesign liegt in
`docs/2026-09-04-redesign-prompt-home-gruppen-profil.md` – **lies diese Datei
zuerst komplett**, bevor du irgendetwas änderst. Sie enthält bereits alles, was
du brauchst: Kontext zum bestehenden Code (Architektur, Design-Tokens,
Datenmodelle), die volle Aufgabenliste (6 nummerierte Abschnitte, Abschnitt 3
mit Unterpunkten a–i), die visuelle Ausrichtung ("Modern Premium"), eine offene
Design-Entscheidung, die Monetarisierungs-Idee, Nicht-Ziele und die
Verifikations-Schritte am Ende. Diese Datei ist die Quelle der Wahrheit für das
Ziel. Wo Messungen ihr widersprechen, gelten die „Wichtigen Zusatz-Hinweise“ unten —
sie sind nach der Spec entstanden und am echten Verhalten geprüft.

Halte dich strikt an die bestehende Architektur (`AppStore`, Repository-
Pattern, Design-Tokens unter `Core/DesignSystem/`) statt Parallelstrukturen zu
bauen – das steht auch so in der Spec-Datei.

## Stand jetzt

**Der Großteil der Spezifikation ist bereits umgesetzt** — auf dem Branch
`feat/music-embeds` (PR soft233-ttv/tod-app#1), 340 Tests grün. **Nicht bei null
anfangen und nichts neu bauen, was es schon gibt.** Lies nach der Spec-Datei als
Zweites `docs/UEBERGABE.md`: dort steht, was fertig ist, was offen ist, was gemessen
wurde und welche Regeln sich das Projekt gegeben hat.

**Fertig:** Abschnitt 1 (Home), 2 (Gruppen-Ansicht), 3a–f (Chat als Hub, Battle,
Rangliste, Swipe-Feed mit Reveal am Kalendertag, Gruppeneinstellungen), 3i (Abschnitt
wählen, als `Submission.section`), 4 (Profil), 5 (Tastatur), 6 (tägliche
Erinnerungen) — und von 3g der Teil, der ohne Developer-Account geht: Apples Vorschau
spielt nativ über die offene iTunes-Search-API (`ITunesCatalog`, `CatalogMatch`,
`CatalogResolver`, `PreviewPlayer`), ohne Treffer fällt der Player aufs
Spotify-Embed zurück, und ein Post trägt `isrc` und `appleMusicID`.

**Offen:**
- **MusicKit** (braucht den bezahlten Account, der noch nicht läuft): als zweiter
  `MusicCatalog` neben `ITunesCatalog` und als eigener Player; die Wahl des Players
  steht an einer Stelle, `TrackPlayerSheet.player(for:catalog:spotifyWebSession:)`.
- **3h Quellen-Icons** — mit den offiziellen Marken-Assets, die der Nutzer
  freigeben muss.

## Wichtige Zusatz-Hinweise

- **Gemessen, und anders als in der Spec:** Apples Vorschauen sind **30 Sekunden**
  lang, nicht „ca. 90“ (vier Songs von 200 bis 354 s, alle 30,0 s). Die
  iTunes-Search-API kennt nur, was im iTunes Store verkauft wird — Frank Oceans
  „Blonde“ fehlt dort ganz —, und sie bietet keinen ISRC-Abgleich; der steckt in der
  Apple-Music-API und braucht den Account.
- **Kein Client-Credentials-Flow für die Spotify-Suche**, auch wenn die Spec ihn
  nennt. Er braucht das Client-Secret, in der App oder hinter einem Proxy, und genau
  das wurde abgeschafft (PKCE, Proxy weg). Die Suche bleibt beim bestehenden Login.
  Nicht einbauen, ohne vorher zu fragen.
- **Offene Design-Entscheidung** (Root-`TabView`): ist getroffen — zwei Tabs, siehe
  `App/RootTabView.swift`.
- **Iterativ arbeiten:** kleine, testbare Schritte. Nach jeder neuen Datei
  `xcodegen generate` und die erzeugte `project.pbxproj` mitcommitten. Reine Logik
  ohne SwiftUI testen, wie `TrackSection`, `Streak`, `CatalogMatch` es vormachen.
- **Bei Unsicherheit:** eine zur Architektur passende Annahme treffen, kurz
  dokumentieren (Code-Kommentar oder Commit-Message) und weitermachen.

## Verifikation am Ende

`xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
muss durchlaufen. Das Ergebnis in eine Datei schreiben und auf „TEST SUCCEEDED“
prüfen — nie `xcodebuild test | grep … && git push`: das `grep` gelingt auch bei
roten Tests, und so ist schon einmal ein roter Stand rausgegangen.
