---
tags: [todapp, plan, redesign]
---

# Redesign, Teil 1: Fundament — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Datenmodelle, der Mini-Player und die neue Navigationsstruktur, auf denen die vier neuen Bildschirme aufbauen — ohne dass ein einziger davon schon gebaut wird.

**Architecture:** Vier Modellergänzungen (echte Kommentare statt Zeichenketten, Tages-Streak, Nutzerprofil, Gruppenbild), dann der Mini-Player als `safeAreaInset` auf der Wurzel, dann der Umbau von sechs Tabs auf zwei plus eine Gruppen-Detailansicht. Reine Logik — Streak-Berechnung, Bild-Rückfall — bleibt ohne SwiftUI testbar, wie `TrackSection` es vormacht.

**Tech Stack:** Swift 6, SwiftUI, iOS 17, Swift Testing, PhotosUI. Keine neuen Abhängigkeiten.

**Spec:** [[2026-09-04-redesign-prompt-home-gruppen-profil|docs/2026-09-04-redesign-prompt-home-gruppen-profil.md]]

## Global Constraints

- Swift 6, iOS 17. Swift Testing only (`@Suite`, `@Test`, `#expect`, `#require`) — niemals XCTest.
- Kein Test geht ins Netz oder an den Keychain.
- Kommentare im Code auf Englisch, **Oberflächentexte auf Deutsch**, informelles „du", keine Ausrufezeichen.
- Nur bestehende Design-Tokens aus `TodApp/Core/DesignSystem/` verwenden, außer wo dieser Plan ausdrücklich einen neuen nennt.
- Nach jeder neuen Quelldatei `xcodegen generate` ausführen und die erzeugte `TodApp.xcodeproj/project.pbxproj` **mit** den Quellen committen.
- Testlauf: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17'`
- Keine neuen Build-Warnungen.
- Alles bleibt In-Memory. Kein Backend, keine neue Musikquelle.

## Zwei Entscheidungen, die dieser Plan trifft

**Navigation.** Der Prompt überlässt mir ausdrücklich, wohin Voten, Reveal, Rangliste,
Chat und Battle wandern. Sie gehen in eine **Gruppen-Detailansicht**, nicht in die
Tab-Leiste. Grund: alle fünf sind an eine Gruppe gebunden — deshalb existiert der
globale Gruppen-Umschalter überhaupt. Sobald Gruppen ein eigener Bereich mit Liste
sind, ist „welche Gruppe" keine App-weite Einstellung mehr, sondern ergibt sich daraus,
wo man ist. Damit fällt der Umschalter weg, und die Tab-Leiste schrumpft von sechs auf
zwei: **Home** und **Gruppen**. Das Profil hängt an einem Knopf oben rechts, kein Tab.
Keine Funktion verschwindet.

**Der Logout-Stub entfällt.** Der Prompt datiert vor dem Auth-Umbau und verlangt für
den Profil-Screen einen „Logout-Button-Stub, keine echte Auth nötig". Die Anmeldung ist
inzwischen echt, und eine funktionierende Abmeldung liegt bereits in `MoreView` — mit
Kontostatus, Fähigkeiten-Hinweis und Rückfrage. Der Profil-Screen aus Plan 2 nimmt sie
auf, statt einen Platzhalter danebenzustellen.

**Deshalb bleibt „Mehr" vorerst ein dritter Tab.** Aufgabe 5 streicht die Tab-Leiste auf
Home und Gruppen zusammen — würde sie „Mehr" gleich mit entfernen, wäre die eben gebaute
Abmeldung von nirgends mehr erreichbar. Sie bleibt stehen, bis der Profil-Bildschirm in
Plan 2 sie übernimmt, und verschwindet erst dann.

---

### Task 1: Echte Kommentare statt Zeichenketten

**Files:**
- Create: `TodApp/Core/Models/Comment.swift`
- Modify: `TodApp/Core/Models/Submission.swift`
- Modify: `TodApp/Core/Repositories/InMemoryRepository.swift`
- Modify: `TodApp/Core/AppStore.swift` (die `Submission`-Konstruktion in `post`)
- Test: `TodAppTests/CommentTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces: `struct Comment: Identifiable, Codable, Equatable` mit `id: Int`, `authorID: String`, `authorName: String`, `text: String`, `postedAt: Date`; `Submission.comments: [Comment]`.

Heute ist `comments: [String]`. Keine einzige View zeigt sie an, gelesen wird das Feld
produktiv nur an einer Stelle (`InMemoryRepository.addComment`) — die Migration ist
darum billig, und sie muss vor dem Kommentarbildschirm passieren.

- [ ] **Step 1: Write the failing test**

`TodAppTests/CommentTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct CommentTests {
    @Test
    func aCommentKeepsItsAuthorAndTime() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let comment = Comment(
            id: 1, authorID: "lena", authorName: "Lena",
            text: "Bester Song heute", postedAt: when
        )

        #expect(comment.authorName == "Lena")
        #expect(comment.postedAt == when)
    }

    /// Posts stored before comments had structure must still decode, so the
    /// field is optional-safe rather than a hard schema break.
    @Test
    func aSubmissionWithoutCommentsDecodes() throws {
        let json = Data("""
        {"id":1,"posterID":"du","track":"Genesis","artist":"Justice",
         "coverColorHex":"#b3527a","comments":[]}
        """.utf8)

        let submission = try JSONDecoder().decode(Submission.self, from: json)

        #expect(submission.comments.isEmpty)
    }

    @Test
    func commentsSurviveARoundTrip() throws {
        let submission = Submission(
            id: 1, posterID: "du", track: "Genesis", artist: "Justice",
            coverColorHex: "#b3527a",
            comments: [
                Comment(id: 1, authorID: "mats", authorName: "Mats",
                        text: "Läuft bei dir", postedAt: Date(timeIntervalSince1970: 0))
            ]
        )

        let decoded = try JSONDecoder().decode(
            Submission.self, from: JSONEncoder().encode(submission)
        )

        #expect(decoded.comments.first?.authorName == "Mats")
        #expect(decoded.comments.first?.text == "Läuft bei dir")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error:"`
Expected: FAIL mit `cannot find 'Comment' in scope`

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Models/Comment.swift`:

```swift
import Foundation

/// One reply under a posted song. Was a bare `String` until the comment screen
/// needed an author and a time to show next to the text.
struct Comment: Identifiable, Codable, Equatable {
    let id: Int
    var authorID: String
    var authorName: String
    var text: String
    var postedAt: Date
}
```

In `Submission.swift` das Feld austauschen:

```swift
    var comments: [Comment]
```

In `InMemoryRepository.swift` jede der sieben `comments:`-Stellen auf `[]` oder auf
echte `Comment`-Werte umstellen. Mindestens eine Submission der Beispieldaten bekommt
zwei echte Kommentare, damit der spätere Bildschirm etwas zu zeigen hat:

```swift
                comments: [
                    Comment(id: 1, authorID: "lena", authorName: "Lena",
                            text: "Der Drop bei 1:12 ist unfassbar",
                            postedAt: Date().addingTimeInterval(-3600)),
                    Comment(id: 2, authorID: "jaro", authorName: "Jaro",
                            text: "Läuft seit gestern bei mir in Dauerschleife",
                            postedAt: Date().addingTimeInterval(-1800))
                ],
```

`addComment` nimmt jetzt einen `Comment` statt eines `String` entgegen. Passe die
Signatur im `SubmissionRepository`-Protokoll und alle Aufrufer an. Die Vergabe der
`id` erfolgt wie bei `Submission`: höchste vorhandene plus eins.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Test run with|✘"`
Expected: PASS. Die Testdateien mit `comments: []` kompilieren unverändert weiter, weil ein leeres Array beide Typen erfüllt.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Models/Comment.swift TodApp/Core/Models/Submission.swift TodApp/Core/Repositories/InMemoryRepository.swift TodApp/Core/AppStore.swift TodAppTests/CommentTests.swift TodApp.xcodeproj/project.pbxproj
git commit -m "Give comments an author and a time"
```

---

### Task 2: Tages-Streak

**Files:**
- Create: `TodApp/Core/Models/Streak.swift`
- Modify: `TodApp/Core/Models/Member.swift`
- Modify: `TodApp/Core/Repositories/InMemoryRepository.swift`
- Test: `TodAppTests/StreakTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces: `Member.postedDates: [Date]` und `Member.currentStreak: Int`; `enum Streak` mit `static func current(from dates: [Date], today: Date, calendar: Calendar) -> Int`.

Die Streak ist die einzige echte Rechnung in diesem Plan, also gehört sie in einen
reinen Typ ohne SwiftUI — wie `TrackSection` es vormacht. Gezählt werden Tage in Folge
bis einschließlich heute; wer heute noch nicht gepostet hat, aber gestern, steht
weiterhin bei seiner Zahl (die Serie ist noch nicht gerissen, der Tag läuft ja noch).

- [ ] **Step 1: Write the failing test**

`TodAppTests/StreakTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
struct StreakTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: today)!
    }

    @Test
    func noPostsIsNoStreak() {
        #expect(Streak.current(from: [], today: today, calendar: calendar) == 0)
    }

    @Test
    func postingTodayOnlyIsOne() {
        #expect(Streak.current(from: [today], today: today, calendar: calendar) == 1)
    }

    @Test
    func threeDaysInARowCountsThree() {
        let dates = [daysAgo(2), daysAgo(1), today]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 3)
    }

    /// The day is not over yet: someone who posted yesterday and the days
    /// before still holds their streak until midnight.
    @Test
    func yesterdayStillCountsWhenTodayIsUnfinished() {
        let dates = [daysAgo(2), daysAgo(1)]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 2)
    }

    @Test
    func aMissedDayEndsTheStreak() {
        let dates = [daysAgo(5), daysAgo(4), daysAgo(1), today]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 2)
    }

    /// Two posts on one day are one day, not two.
    @Test
    func twoPostsOnTheSameDayCountOnce() {
        let dates = [today, today.addingTimeInterval(120)]

        #expect(Streak.current(from: dates, today: today, calendar: calendar) == 1)
    }

    @Test
    func postsFromLongAgoDoNotCount() {
        #expect(Streak.current(from: [daysAgo(30)], today: today, calendar: calendar) == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error:"`
Expected: FAIL mit `cannot find 'Streak' in scope`

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Models/Streak.swift`:

```swift
import Foundation

/// How many days in a row someone has posted. Pure arithmetic over dates, so
/// it can be tested without a view, a store, or a clock.
enum Streak {
    /// Counts back from today. A gap ends the count. Today itself may be
    /// missing without breaking the streak -- the day is not over, and
    /// resetting someone's number at midnight for a day they can still finish
    /// would be the wrong kind of honest.
    static func current(
        from dates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            // Today is still open. Start counting from yesterday instead.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return count
    }
}
```

In `Member.swift` ergänzen:

```swift
    /// The days this member posted on, newest last. The streak is derived from
    /// these rather than stored, so it cannot drift out of sync with reality.
    var postedDates: [Date]

    var currentStreak: Int {
        Streak.current(from: postedDates)
    }
```

`Member` ist `Codable`; ein neues nicht-optionales Feld bricht das Dekodieren
bestehender Daten. Da alles In-Memory ist, genügt es, die Beispieldaten in
`InMemoryRepository` zu ergänzen — gib der eigenen Person eine Serie von fünf Tagen und
den anderen unterschiedliche Längen, damit die Home-Ansicht später etwas Echtes zeigt.

`markPosted` bzw. die Stelle, an der `hasPostedToday` gesetzt wird, hängt zusätzlich
`Date()` an `postedDates` an.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Test run with|✘"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Models/Streak.swift TodApp/Core/Models/Member.swift TodApp/Core/Repositories/InMemoryRepository.swift TodAppTests/StreakTests.swift TodApp.xcodeproj/project.pbxproj
git commit -m "Count how many days in a row someone posted"
```

---

### Task 3: Nutzerprofil und Gruppenbild

**Files:**
- Create: `TodApp/Core/Models/UserProfile.swift`
- Modify: `TodApp/Core/Models/Group.swift`
- Modify: `TodApp/Core/AppStore.swift`
- Test: `TodAppTests/UserProfileTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces: `struct UserProfile: Codable, Equatable` mit `id: String`, `name: String`, `imageData: Data?`; `AppStore.profile: UserProfile` und `AppStore.updateProfile(name:imageData:)`; `Group.imageData: Data?`.

Heute ist der eigene Nutzer nur `currentUserID = "du"` plus ein Flag auf `Member`, und
eine Gruppe hat nur `icon: String` als Emoji. Beide brauchen ein Bild — und einen
Rückfall, wenn keins gesetzt ist.

- [ ] **Step 1: Write the failing test**

`TodAppTests/UserProfileTests.swift`:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct UserProfileTests {
    @Test
    func aFreshStoreHasAProfileForTheCurrentUser() {
        let store = AppStore()

        #expect(store.profile.id == "du")
        #expect(!store.profile.name.isEmpty)
    }

    @Test
    func renamingSticks() {
        let store = AppStore()

        store.updateProfile(name: "Lennet", imageData: nil)

        #expect(store.profile.name == "Lennet")
    }

    /// Passing no image must not wipe one that was already chosen -- the
    /// profile screen edits name and picture independently.
    @Test
    func renamingKeepsAnExistingPicture() {
        let store = AppStore()
        let picture = Data([0x01, 0x02])
        store.updateProfile(name: "Lennet", imageData: picture)

        store.updateProfile(name: "Lenny", imageData: nil)

        #expect(store.profile.imageData == picture)
        #expect(store.profile.name == "Lenny")
    }

    @Test
    func aBlankNameIsRefused() {
        let store = AppStore()
        let before = store.profile.name

        store.updateProfile(name: "   ", imageData: nil)

        #expect(store.profile.name == before)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error:"`
Expected: FAIL mit `value of type 'AppStore' has no member 'profile'`

- [ ] **Step 3: Write minimal implementation**

`TodApp/Core/Models/UserProfile.swift`:

```swift
import Foundation

/// The person using the app. Until now they existed only as the string "du"
/// and a flag on `Member`; the profile screen needs somewhere to put a name
/// and a picture.
struct UserProfile: Codable, Equatable {
    let id: String
    var name: String
    /// Raw image bytes rather than a URL: everything here is in memory, and a
    /// picked photo has no address to point at.
    var imageData: Data?
}
```

In `Group.swift` ergänzen:

```swift
    /// A real picture for the group. `icon` stays as the fallback, so a group
    /// without one still shows something rather than a grey square.
    var imageData: Data?
```

In `AppStore.swift`:

```swift
    private(set) var profile = UserProfile(id: "du", name: "Du", imageData: nil)

    /// `imageData: nil` means "leave the picture alone", not "remove it" --
    /// the profile screen edits the two independently.
    func updateProfile(name: String, imageData: Data?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { profile.name = trimmed }
        if let imageData { profile.imageData = imageData }
    }
```

`Group.imageData` ist optional, also bricht kein bestehender Aufrufer.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Test run with|✘"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TodApp/Core/Models/UserProfile.swift TodApp/Core/Models/Group.swift TodApp/Core/AppStore.swift TodAppTests/UserProfileTests.swift TodApp.xcodeproj/project.pbxproj
git commit -m "Give the user a profile and groups a picture"
```

---

### Task 4: Mini-Player

**Files:**
- Create: `TodApp/Features/Player/MiniPlayerBar.swift`
- Modify: `TodApp/App/RootTabView.swift`
- Test: `TodAppTests/MiniPlayerTests.swift`

**Interfaces:**
- Consumes: `AppStore`s bereits vorhandene Spiegelung von `provider.playbackUpdates()` — die App weiß schon, was gerade läuft. Lies in `AppStore.swift` nach, wie die Eigenschaft heißt, und benutze sie; baue keinen zweiten Zustand daneben.
- Produces: `MiniPlayerBar`, eingehängt als `.safeAreaInset(edge: .bottom)`.

Der Prompt verlangt einen app-weiten Player-Zustand. Der **existiert bereits**: beim
Beheben eines Fehlers, bei dem der Knopf „Stopp" zeigte, obwohl die Wiedergabe längst
zu Ende war, hat der Provider einen Zustandsstrom bekommen und der Store spiegelt ihn.
Diese Aufgabe baut nur noch die Leiste, die ihn anzeigt.

Sichtbar **nur solange etwas spielt**. Kein Dauerelement.

- [ ] **Step 1: Write the failing test**

`TodAppTests/MiniPlayerTests.swift` — geprüft wird der Zustand, nicht die View:

```swift
import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct MiniPlayerTests {
    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )
    }

    private let source = TrackSource(
        service: .spotify, serviceTrackID: "abc",
        pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
    )

    /// The bar exists only while something plays, so the store must report
    /// nothing playing on a fresh launch.
    @Test
    func nothingPlaysOnAFreshStore() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        #expect(store.nowPlaying == nil)
    }

    @Test
    func stoppingClearsWhatIsPlaying() async throws {
        let provider = FakeMusicProvider(capabilities: everything)
        let store = AppStore(provider: provider)
        await store.signIn()
        try await provider.play(source, from: nil)

        await provider.stop()

        // Give the store's stream consumer a turn to observe the change.
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.nowPlaying == nil)
    }
}
```

Heißt die Eigenschaft im Store anders als `nowPlaying`, passe den Test an den
tatsächlichen Namen an, statt einen zweiten einzuführen.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error:|✘"`
Expected: FAIL, solange der Name nicht stimmt — das ist der Zweck dieses Schritts.

- [ ] **Step 3: Write minimal implementation**

`TodApp/Features/Player/MiniPlayerBar.swift`:

```swift
import SwiftUI

/// A thin bar that appears only while something is playing. Tapping it opens
/// the full song view; the button stops playback. It reads the store's mirror
/// of the provider's playback state rather than keeping its own idea of what
/// is playing -- a view that guesses is exactly the bug this app already had.
struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        if let playing = store.nowPlaying {
            HStack(spacing: 12) {
                AsyncImage(url: playing.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.todSurface3)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Spielt gerade")
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextDim)

                Spacer()

                Button {
                    Task { await store.stopPlayback() }
                } label: {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Color.todText)
                        .padding(8)
                }
                .accessibilityLabel("Wiedergabe pausieren")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.todLine).frame(height: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }
}
```

Braucht `AppStore` noch ein `stopPlayback()`, das an den Provider durchreicht, ergänze
es dort — eine Zeile, die `await provider.stop()` ruft.

In `RootTabView.swift` unten einhängen, neben dem bestehenden oberen `safeAreaInset`:

```swift
        .safeAreaInset(edge: .bottom) {
            MiniPlayerBar(onOpen: { /* Task 6 verbindet das mit der Song-Ansicht */ })
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Test run with|✘"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TodApp/Features/Player/MiniPlayerBar.swift TodApp/App/RootTabView.swift TodApp/Core/AppStore.swift TodAppTests/MiniPlayerTests.swift TodApp.xcodeproj/project.pbxproj
git commit -m "Show a mini player while something is playing"
```

---

### Task 5: Drei Tabs statt sieben

**Files:**
- Create: `TodApp/Features/Groups/GroupDetailView.swift`
- Modify: `TodApp/App/RootTabView.swift`
- Test: keiner — reine Navigationsverdrahtung; ein Test, der nur prüft, dass eine View existiert, kann nicht scheitern. Dieses Projekt hat aus genau dem Grund schon zwei Tests gelöscht.

**Interfaces:**
- Consumes: `TodayView`, `VotingView`, `RevealView`, `LeaderboardView`, `ChatView`, `BattleView`.
- Produces: `GroupDetailView`, das die fünf gruppengebundenen Ansichten beherbergt; eine Tab-Leiste mit drei Einträgen (Home, Gruppen, Mehr).

Die Begründung steht oben unter „Zwei Entscheidungen". Wichtig: **keine Funktion
verschwindet**, sie ziehen nur um.

Dieser Task legt den Gruppen-Tab noch nicht als Instagram-Feed an — das ist Plan 2. Er
zeigt vorerst die bestehende Gruppenliste als schlichte Liste, damit die Navigation
lauffähig ist und Plan 2 die Liste nur noch ersetzen muss.

- [ ] **Step 1: Write GroupDetailView**

```swift
import SwiftUI

/// Everything that belongs to one group. Voting, Reveal, the leaderboard, the
/// chat and battles all read `AppStore.currentGroup`, which is why the app used
/// to carry a group switcher on every screen. Once a group is a place you go
/// to, "which group" follows from where you are.
struct GroupDetailView: View {
    @Environment(AppStore.self) private var store
    let group: Group

    var body: some View {
        List {
            NavigationLink("Voten") { VotingView() }
            NavigationLink("Reveal") { RevealView() }
            NavigationLink("Rangliste") { LeaderboardView() }
            NavigationLink("Chat") { ChatView() }
            NavigationLink("Battle") { BattleView() }
        }
        .listStyle(.plain)
        .font(.todBody(16))
        .foregroundStyle(Color.todText)
        .scrollContentBackground(.hidden)
        .background(Color.todBackground)
        .navigationTitle(group.name)
        .onAppear { store.selectGroup(group.id) }
    }
}
```

`onAppear` setzt die Gruppe, weil die fünf Ansichten weiterhin `currentGroup` lesen —
diesen Plan als Umzug halten, nicht als Umbau ihrer Datenquelle.

- [ ] **Step 2: Rewrite RootTabView**

```swift
import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                List(store.groups) { group in
                    NavigationLink(group.name) { GroupDetailView(group: group) }
                }
                .listStyle(.plain)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .scrollContentBackground(.hidden)
                .background(Color.todBackground)
                .navigationTitle("Gruppen")
            }
            .tabItem { Label("Gruppen", systemImage: "person.2.fill") }

            // Stays until Plan 2's profile screen takes over the sign-out that
            // lives here. Removing it now would strand the only way out of a
            // Spotify session.
            NavigationStack { MoreView() }
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
        }
        .tint(.todAccent)
        .safeAreaInset(edge: .bottom) {
            MiniPlayerBar(onOpen: {})
        }
    }
}
```

Der obere `GroupSwitcher` und sein `safeAreaInset` entfallen ersatzlos — lösche die
`private struct GroupSwitcher` aus derselben Datei mit.

- [ ] **Step 3: Run the suite**

Run: `xcodegen generate && xcodebuild test -scheme TodApp -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Test run with|✘|error:"`
Expected: PASS, unverändert viele Tests — es wurde keine Logik angefasst.

- [ ] **Step 4: Sichtprüfung**

Baue und starte die App im Simulator und geh jeden der fünf umgezogenen Bereiche einmal
an. Ein Test kann hier nichts beweisen; das Auge schon. Halte im Bericht fest, was du
gesehen hast.

- [ ] **Step 5: Commit**

```bash
git add TodApp/Features/Groups/GroupDetailView.swift TodApp/App/RootTabView.swift TodApp.xcodeproj/project.pbxproj
git commit -m "Move the group-scoped screens into the group"
```

---

## Was dieser Plan bewusst nicht tut

Home, der Instagram-artige Gruppen-Feed, die Kommentaransicht, der Profil-Bildschirm
und die visuelle Ausrichtung („Modern Premium", Cover-Glow, Glas, Streak-Farbe) sind
**Plan 2**. Dieser Plan schafft nur die Grundlagen, auf denen sie stehen: echte
Kommentare, eine Streak, ein Profil, Gruppenbilder, den Mini-Player und die
Navigationsstruktur.
