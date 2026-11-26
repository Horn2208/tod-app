---
tags: [todapp, plan, backend]
---

# Die App an die Datenbank anschließen — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Mit Konto liegen Gruppen, Mitglieder, Posts, Kommentare, Bewertungen, Hidden Gems, Chat, Profil und Bilder in Supabase statt im Speicher, und ein neues Konto kann eine Gruppe anlegen oder per Code beitreten.

**Architecture:** `SupabaseRepository` erfüllt dieselben Protokolle wie `InMemoryRepository` und bleibt dünn: Abfragen und Schreiben. Alles, was sich ohne Netz prüfen lässt, liegt daneben als reine Typen — Zeilen (`BackendRecords`), der Zusammenbau zu `Group` (`GroupAssembly`), Rundentag, Punkte (`ScoreTally`) und die Übersetzung von Serverfehlern (`BackendError`). `AppStore` nimmt die Identität aus dem Konto statt aus `"du"`, lädt das Profil vom Server und kann Gruppen anlegen und beitreten. Ohne `Config/Secrets.xcconfig` und in den Tests bleibt alles wie bisher im Speicher.

**Tech Stack:** Swift 6, SwiftUI, iOS 17, Swift Testing, Supabase-Swift 2.55.2 (PostgREST, Storage), fest gepinnt.

**Spec:** Abschnitt 7 und Fahrplan-Phase 1 in `docs/2026-09-04-redesign-prompt-home-gruppen-profil.md`; Schema in `supabase/migrations/20260917095131_initial_schema.sql` und `…095311_pictures_and_vote_key_index.sql`.

## Global Constraints

- Kein Test geht ins Netz. Der Netzteil (`SupabaseRepository`) wird im Simulator gegen das echte Projekt geprüft, nicht in Unit-Tests.
- Tests mit Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), niemals XCTest.
- Kommentare und Commit-Nachrichten auf Englisch, Texte in der Oberfläche auf Deutsch, informelles „du“, keine Ausrufezeichen.
- `InMemoryRepository` bleibt und bleibt der Standard für Tests und Previews.
- Was der Server setzt (Autor, Zeit, Runde, ids), schickt die App nicht mit — die Rechte lassen es ohnehin nicht zu.
- Nie den `service_role`-Schlüssel in der App.
- Ein Rundentag ist ein Kalendertag; die Datenbank rechnet in Europe/Berlin, die App im Gerätekalender. Für Leute in Deutschland ist das dasselbe.
- Nach jeder neuen Quelldatei `xcodegen generate` und die erzeugte `project.pbxproj` mitcommitten.
- Testlauf: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
- Commits nur mit ausdrücklichen Pfaden (`git commit -m … -- <pfade>`): Im Index liegen noch fremde, vorgemerkte Änderungen (`MusicKitCatalog.swift`, `SpotifyProvider.swift`, `.obsidian/graph.json`), die nicht mitgehen dürfen.

## Entscheidungen

- **Einladen heißt jetzt Code.** „Mitglied per Name hinzufügen“ gibt es mit echten Konten nicht — hinter einem getippten Namen steht niemand. Die Einstellungen erzeugen einen Code (`group_invites`, 7 Tage gültig) zum Weitergeben, beitreten geht über `join_group(code)`. Das gilt auch für die Daten im Speicher.
- **Ein neues Konto hat keine Gruppe.** Home und Gruppen zeigen dann „Gruppe erstellen“ und „Mit Code beitreten“ statt eines endlosen Ladekreises.
- **Die gewählte Gruppe fällt auf die erste zurück**, wenn es die gewählte nicht gibt (vorher stand `"lnc"` fest).
- **Bewerten ohne Upsert.** PostgREST schreibt bei einem Upsert alle mitgeschickten Spalten, und `submission_id`/`group_id`/`round_day` dürfen nicht geändert werden. Also: erst `update`, und wenn keine Zeile betroffen war, `insert`. Ebenso beim Hidden Gem: lesen, dann löschen, ändern oder anlegen.
- **Seitenweise lesen.** Supabase gibt höchstens 1000 Zeilen auf einmal zurück; Posts, Stimmen und Gems werden in Seiten zu 1000 gelesen.
- **Chat:** die letzten 200 Nachrichten pro Gruppe, ohne Live-Updates (später, Phase 1 Rest). Neu geladen wird beim Zurückkommen in die App und per Herunterziehen.
- **Bilder** werden vor dem Hochladen auf höchstens 1024 px verkleinert (JPEG), unter einem neuen Dateinamen je Upload gespeichert, die alte Datei danach gelöscht. Geladene Bilder hält das Repository nach Pfad im Speicher.
- **Battles** haben noch keine Tabelle: Mit Datenbank gibt es kein laufendes Battle, die Ansicht sagt das schon.
- **Premium** bleibt der lokale Schalter im Profil; der Server-Wert `is_premium` kommt erst mit StoreKit.
- **Fehler werden sichtbar.** Bisher zeigte nur das Posten `lastError`; mit Netz kann jedes Schreiben scheitern. Ein Banner oben in der App sagt es.
- **Testkonten nur im Debug-Build.** Für die Prüfung im Simulator (dort gibt es keinen Apple Account) meldet sich ein Debug-Build mit E-Mail und Passwort aus Startumgebungsvariablen an. Nichts davon steht im Repo; ein Release-Build kennt den Weg nicht.

---

### Task 1: Zeilen und Zusammenbau

**Files:**
- Create: `TodApp/Core/Backend/BackendRecords.swift`
- Create: `TodApp/Core/Backend/GroupAssembly.swift`
- Test: `TodAppTests/GroupAssemblyTests.swift`

**Interfaces:**
- Produces: `GroupRecord`, `MemberRecord`, `ProfileRecord`, `SubmissionRecord`, `CommentRecord`, `ChatRecord`, `VoteRecord`, `GemRecord` (alle `Decodable, Sendable`, snake_case-Schlüssel), `BackendRecords.decoder` (= `PostgrestClient.Configuration.jsonDecoder`), `GroupAssembly.groups(from:submissions:messages:me:now:calendar:) -> [Group]`, `GroupAssembly.initials(of:) -> String`, `CoverColor.hex(forTrack:)` (besteht).

- [x] Tests schreiben: eine PostgREST-förmige JSON-Antwort (Gruppe mit eingebetteten `group_members(user_id, profiles(name, avatar_path))`, Posts mit eingebetteten `comments`, Zeitstempel mit Mikrosekunden) dekodiert; `groups(from:)` ordnet Posts und Chat der richtigen Gruppe zu, setzt `isCurrentUser`/`isFromCurrentUser` nach `me`, leitet `postedDates` aus den eigenen Posts ab, nennt Kommentarautoren nach ihrem Profil (und „Jemand“, wenn das Profil nicht sichtbar ist), baut `TrackSource` nur bei vollständiger Quelle, `TrackSection` nur bei beiden Grenzen, `roundEndsAt` = nächste Mitternacht, sortiert Gruppen nach Name und Posts nach Zeit, liest `invite_policy` `creator_only` als `.creatorOnly`.
- [x] Rot sehen, umsetzen, grün sehen.
- [x] Commit: `Read the database's rows into the app's groups`

### Task 2: Rundentag, Punkte, Serverfehler

**Files:**
- Create: `TodApp/Core/Backend/RoundDay.swift`
- Create: `TodApp/Core/Backend/ScoreTally.swift`
- Create: `TodApp/Core/Backend/BackendError.swift`
- Modify: `TodApp/Core/TodAppError.swift` (neu: `.alreadyPosted`, `.inviteInvalid`)
- Modify: `TodApp/Features/PostSong/PostSongModel.swift` (`message(for:)`: Texte für `.notFound`, `.notAllowed`, `.roundClosed`, `.alreadyPosted`, `.inviteInvalid`)
- Test: `TodAppTests/BackendMappingTests.swift`

**Interfaces:**
- Produces: `RoundDay.string(for: Date, calendar: Calendar) -> String` („yyyy-MM-dd“ aus den Kalenderteilen), `RoundDay.berlin(_ date: Date) -> String`, `ScoreTally.scores(submissionIDs: [Int], votes: [VoteRecord], gems: [GemRecord]) -> [RoundScore]`, `VoteRecord.vote -> Vote?`, `BackendError.map(_ error: Error, context: BackendError.Context) -> TodAppError` mit `Context` = `.read, .post, .vote, .join, .write`.
- Fehlerregeln: PostgREST `42501` → `.roundClosed` bei `.vote`, sonst `.notAllowed`; `23505` → `.alreadyPosted` bei `.post`; `P0002` oder `22P02` → `.inviteInvalid` bei `.join`, sonst `.notFound`; `PGRST116` → `.notFound`; `StorageError` mit Status 403 → `.notAllowed`; `URLError` → `.network`; ein `TodAppError` bleibt, was er ist; alles andere → `.network`.

- [x] Tests: Mitternacht und Monatsgrenze beim Rundentag; Punkte zählen auch ungewertete Posts als 0, Gems ohne Punktwirkung, fremde Posts in den Zeilen zählen nicht; jede Fehlerregel oben einmal; `message(for:)` für die neuen Fälle.
- [x] Rot, umsetzen, grün.
- [x] Commit: `Name a round's day, tally its scores, and say what a server error means`

### Task 3: Protokolle, Speicher-Repository, Attrappen

**Files:**
- Modify: `TodApp/Core/Repositories/GroupRepository.swift` — `addMember(named:to:asking:)` entfällt; neu `createGroup(name:icon:) async throws -> String`, `createInvite(groupID:asking:) async throws -> GroupInvite`, `joinGroup(code:asking:) async throws -> String`.
- Create: `TodApp/Core/Repositories/ProfileRepository.swift` — `fetchProfile(userID:) async throws -> UserProfile`, `updateProfile(userID:name:imageData:) async throws`.
- Create: `TodApp/Core/Models/GroupInvite.swift` — `GroupInvite(code:groupID:expiresAt:)`, `InviteCode.normalized(_:)`, `InviteCode.isPlausible(_:)` (16 Hex-Zeichen), `InviteCode.display(_:)` (Viererblöcke), `NewGroupDraft.name(_:)`/`icon(_:)` (1–40 Zeichen; ein Zeichen, sonst 🎵).
- Modify: `TodApp/Core/Repositories/InMemoryRepository.swift` — die neuen Methoden, `ProfileRepository`.
- Modify: `TodApp/Features/Chat/GroupSettingsView.swift` nur so weit, dass es baut (der neue Einladeblock kommt in Task 6).
- Modify: `TodAppTests/AppStoreTests.swift` (`MockGroupRepository`), `TodAppTests/GroupSettingsTests.swift`.
- Test: `TodAppTests/GroupInviteTests.swift`

- [x] Tests: Code-Normalisierung (Leerzeichen, Bindestriche, Großbuchstaben), Plausibilität, Anzeige; Gruppenname/-zeichen; im Speicher: eine neue Gruppe hat den Anfragenden als Ersteller und einziges Mitglied; einladen darf nur, wen `GroupPermissions.mayInvite` lässt; ein Code führt zur Gruppe, ein unbekannter wirft `.inviteInvalid`; das Profil lässt sich lesen und umbenennen, ein leerer Name bleibt ohne Wirkung.
- [x] Die alten `addMember`-Tests werden zu Einladungs-Tests.
- [x] Rot, umsetzen, grün, Commit: `Invite by code and keep the profile behind a repository`

### Task 4: AppStore mit echter Identität

**Files:**
- Modify: `TodApp/Core/AppStore.swift`
- Modify: `TodApp/App/TodApp.swift` (`AppStore.live()`)
- Test: `TodAppTests/AppStoreBackendTests.swift`

**Interfaces:**
- Produces: `AppStore.currentUserID` (Konto-id, sonst `"du"`), `hasLoadedGroups`, `currentGroup` mit Rückfall auf die erste Gruppe, `loadProfile()`, `updateProfile(name:imageData:) async`, `createGroup(name:icon:) async -> Bool`, `createInvite() async -> GroupInvite?`, `joinGroup(code:) async -> Bool`, `refresh() async`, `static func live() -> AppStore`.
- `signOut()` leert zusätzlich Profil, Stimmen, Punkte, Saison und Gruppenwahl.

- [x] Tests: mit wiederhergestelltem Konto stimmen `currentUserID`, `profile.id` und der geladene Name; eine Stimme trägt die Konto-id; ohne passende Wahl ist die erste Gruppe die aktuelle; `hasLoadedGroups` erst nach dem Laden; eine neue Gruppe wird gewählt; Beitreten wählt die Gruppe, ein falscher Code setzt `lastError = .inviteInvalid` und liefert `false`; Abmelden leert alles; ein Profilname landet im Repository; der lokale Premium-Schalter übersteht das Neuladen des Profils.
- [x] Rot, umsetzen, grün, Commit: `Take the user from the account, and let a new account start or join a group`

### Task 5: SupabaseRepository

**Files:**
- Create: `TodApp/Core/Repositories/SupabaseRepository.swift`
- Create: `TodApp/Core/Backend/ImageDownscale.swift`
- Test: `TodAppTests/ImageDownscaleTests.swift`

**Interfaces:**
- Consumes: alles aus Task 1–3.
- `actor SupabaseRepository: GroupRepository, SubmissionRepository, VoteRepository, ChatRepository, BattleRepository, ProfileRepository`, `init(client: SupabaseClient)`.
- Abfragen: `groups?select=id,name,icon,image_path,creator_id,invite_policy,group_members(user_id,profiles(name,avatar_path))&order=name`; `submissions?select=*,comments(id,author_id,body,created_at)&group_id=in.(…)&order=posted_at,id` seitenweise; `chat_messages?group_id=eq.…&order=created_at.desc&limit=200` je Gruppe; `votes`/`hidden_gems` nach `group_id` und `round_day` (bzw. `round_day=lt.<heute>`) seitenweise; `rpc/join_group`; `group_invites` einfügen mit `select()`.
- `ImageDownscale.jpeg(from: Data, maxPixel: Int = 1024) -> Data?`

- [x] Test: ein großes Bild kommt höchstens 1024 px groß als JPEG zurück, ein kleines wird nicht vergrößert, Unsinn gibt `nil`.
- [x] Repository schreiben; bauen ohne Warnungen.
- [x] Commit: `Talk to Supabase through the same repositories`

### Task 6: Oberfläche

**Files:**
- Create: `TodApp/Features/Groups/GroupEntryViews.swift` (`NoGroupsView`, `NewGroupView`, `JoinGroupView`)
- Create: `TodApp/Features/Shared/ErrorBanner.swift`
- Modify: `TodayView.swift`, `GroupsFeedView.swift` (leerer Zustand, „+“-Menü, Herunterziehen), `GroupSettingsView.swift` (Einladungscode mit Teilen, Umbenennen entprellt), `ProfileView.swift` (Name entprellt, Profil über den Store), `ChatView.swift` (Herunterziehen), `RootTabView.swift` (Banner), `TodApp.swift` (Neuladen beim Zurückkommen)

- [x] Bauen, Tests grün, im Simulator ohne Backend durchsehen (Speicher-Daten): Einstellungen zeigen einen Code, „+“ öffnet beide Blätter.
- [x] Commit: `Start or join a group from an empty app, and invite with a code`

### Task 7: Prüfung gegen das echte Projekt

> Stand 18. September: Debug-Anmeldung gebaut (`-anonymousSignIn` statt Testkonten mit
> Passwort). Der Durchlauf selbst wartet darauf, dass das Projekt anonyme Anmeldungen
> erlaubt; die Abfragen sind gegen das Schema geprüft.

**Files:**
- Modify: `TodApp/Core/Account/AccountService.swift`, `SupabaseAccountService.swift`, `TodApp/App/TodApp.swift` (nur `#if DEBUG`: Anmeldung mit `TODAPP_DEBUG_EMAIL`/`TODAPP_DEBUG_PASSWORD`)

- [ ] Nutzer A (Simulator 1, anonym): Gruppe anlegen, Code erzeugen, posten, kommentieren, Chat, Profilname, Profil- und Gruppenbild.
- [ ] Nutzer B (Simulator 2, anonym): mit Code beitreten, sieht A's Post und Namen, bewertet, setzt Gem, kann den eigenen Post nicht bewerten.
- [ ] Per SQL einen Post und Stimmen für gestern anlegen, Aufdeckung und Saisontabelle prüfen.
- [ ] Berater (`get_advisors`) lesen. Testkonten danach löschen.
- [x] Commit: `Let a debug build sign in without Apple, for the simulator`

### Task 8: Übergabe und unabhängige Prüfung

- [x] `docs/UEBERGABE.md` und `docs/TodApp.md` nachziehen.
- [x] Ein Prüfer (`agy`, Gemini 3.1 Pro, ohne Werkzeuge, Diff im Auftrag) über die Commits; Befunde am Code prüfen (6 von 6 bestätigt, behoben in `83645c5`).
- [ ] Sauberer Ordner (`git worktree`) baut und testet grün; pushen.
