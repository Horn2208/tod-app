# TodApp — SwiftUI Architecture Spec

Target: iOS 17+ (enables `@Observable` and `NavigationStack`). Source design: `tod-prototype.html` (see `brand-spec.md`, `direction-approved.md`).

## 1. Data model

Derived directly from the prototype's `GROUPS` object (source lines 773–846), not guessed. Each `Group` is one aggregate root.

```swift
struct Group: Identifiable, Codable {
    let id: String                  // e.g. "lnc"
    var name: String                // "Late Night Crew"
    var icon: String                // emoji, e.g. "🌙"
    var members: [Member]
    var roundEndsAt: Date           // replaces prototype's countdown `secs`
    var submissions: [Submission]
    var board: [BoardEntry]
    var chatMessages: [ChatMessage]
    var activeBattle: Battle?
}

struct Member: Identifiable, Codable {
    let id: String
    var name: String
    var isCurrentUser: Bool         // prototype's `you`
    var hasPostedToday: Bool        // prototype's `done`
}

struct Submission: Identifiable, Codable {
    let id: Int
    var posterID: String
    var track: String
    var artist: String
    var coverColorHex: String       // placeholder art; prototype uses flat hex swatches, no real cover art
    var comments: [String]
}

struct Vote: Codable {
    var voterID: String
    var submissionID: Int
    var rating: Rating
    var isHiddenGem: Bool           // prototype's per-round single `gemId`; enforce "one true value per voter per round" at the repository layer
}

enum Rating: Int, Codable, CaseIterable {
    case awful = -2, meh = -1, ok = 0, good = 1, banger = 2

    var label: String {             // German labels from RATE_LABELS, source line 850
        switch self {
        case .awful: "Aussetzer"
        case .meh: "Naja"
        case .ok: "Ok"
        case .good: "Gut"
        case .banger: "Banger"
        }
    }
}

struct BoardEntry: Identifiable, Codable {
    var id: String { name }
    var name: String
    var tag: String                 // 2-letter initials
    var points: Int
    var subtitle: String            // e.g. "6 Siege · 2 Battles · Quiz-Master Pop"
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var authorTag: String
    var authorName: String
    var text: String
    var isFromCurrentUser: Bool
}

struct Battle: Codable {
    var mode: BattleMode
    var player1: BattleEntry
    var player2: BattleEntry
    var diceArtists: [String]       // pool shown for Künstler-Würfel mode
}

enum BattleMode: String, Codable {
    case free = "Frei"
    case artistDice = "Künstler-Würfel"
    case aux = "Aux Battle"
}

struct BattleEntry: Codable {
    var name: String
    var track: String
    var artist: String
    var coverColorHex: String
    var percentage: Int             // live vote share
}
```

That's 9 Codable types (`Group`, `Member`, `Submission`, `Vote`, `Rating`, `BoardEntry`, `ChatMessage`, `Battle`, `BattleMode`, `BattleEntry` — 10 counting both enums, matching prior estimate now confirmed against source).

**Deliberate change from the prototype:** the prototype stores `ratings`/`gemId` inline on the group as if there's only one voter (a demo shortcut). The real app needs a proper `Vote` record keyed by `(voterID, submissionID)` so multiple members can vote independently — this is the one place the Swift model is *more* correct than the HTML prototype's demo-data shortcut, not a new design decision.

## 2. Repository architecture

Single `@Observable` `AppStore` is the only thing Views talk to. `AppStore` delegates all persistence to `Repository` protocols; Views never touch a repository directly.

```
View ──▶ @Environment(AppStore.self) ──▶ AppStore ──▶ Repository protocols ──▶ InMemoryRepository (default impl)
```

Six protocols, one per aggregate (matches the six GROUPS sub-collections):

```swift
protocol GroupRepository {
    func fetchGroups() async throws -> [Group]
    func fetchGroup(id: String) async throws -> Group
}

protocol SubmissionRepository {
    func submit(_ submission: Submission, to groupID: String) async throws
    func addComment(_ text: String, submissionID: Int, groupID: String) async throws
}

protocol VoteRepository {
    func castVote(_ vote: Vote, groupID: String) async throws
    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws
    func submitVotes(voterID: String, groupID: String) async throws
}

protocol LeaderboardRepository {
    func fetchBoard(groupID: String) async throws -> [BoardEntry]
}

protocol ChatRepository {
    func sendMessage(_ message: ChatMessage, groupID: String) async throws
    func fetchMessages(groupID: String) async throws -> [ChatMessage]
}

protocol BattleRepository {
    func startBattle(_ battle: Battle, groupID: String) async throws
    func fetchActiveBattle(groupID: String) async throws -> Battle?
}
```

`InMemoryRepository` implements all six protocols against an in-process `[String: Group]` dictionary seeded with the prototype's two demo groups (`lnc`, `wg`) so the app is runnable/demoable with zero backend. A future networked repository can implement the same six protocols without touching `AppStore` or any View.

`AppStore` (sketch):

```swift
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: String = "lnc"

    private let groupRepo: GroupRepository
    private let submissionRepo: SubmissionRepository
    private let voteRepo: VoteRepository
    private let leaderboardRepo: LeaderboardRepository
    private let chatRepo: ChatRepository
    private let battleRepo: BattleRepository

    init(groupRepo: GroupRepository = InMemoryRepository.shared,
         submissionRepo: SubmissionRepository = InMemoryRepository.shared,
         voteRepo: VoteRepository = InMemoryRepository.shared,
         leaderboardRepo: LeaderboardRepository = InMemoryRepository.shared,
         chatRepo: ChatRepository = InMemoryRepository.shared,
         battleRepo: BattleRepository = InMemoryRepository.shared) { ... }

    var currentGroup: Group? { groups.first { $0.id == currentGroupID } }

    func selectGroup(_ id: String) { currentGroupID = id }
    func loadGroups() async throws { groups = try await groupRepo.fetchGroups() }
    func submit(_ submission: Submission) async throws { ... }
    func castVote(_ rating: Rating, for submissionID: Int) async throws { ... }
    func sendMessage(_ text: String) async throws { ... }
    // etc — one method per user-facing action, each a thin pass-through to the matching repo + local state refresh
}
```

## 3. Folder structure (feature-oriented)

```
TodApp/
  App/
    TodApp.swift              // @main App entry, injects AppStore via .environment
  Core/
    Models/                   // Group, Member, Submission, Vote, Rating, BoardEntry, ChatMessage, Battle, BattleMode, BattleEntry
    Repositories/
      GroupRepository.swift   // protocol
      SubmissionRepository.swift
      VoteRepository.swift
      LeaderboardRepository.swift
      ChatRepository.swift
      BattleRepository.swift
      InMemoryRepository.swift  // single class conforming to all six + seed data
    AppStore.swift
    DesignSystem/
      Color+Tokens.swift      // maps brand-spec.md hex values to Color
      Font+Tokens.swift       // Unbounded/Manrope/JetBrains Mono wrappers
  Features/
    Today/         // Heute tab: avatar row, composer, countdown
    Voting/         // Voten tab: rate cards, hidden-gem picker
    Reveal/
    Leaderboard/    // Rangliste tab
    Chat/
    Battle/
  Resources/
    Fonts/          // bundled .ttf/.otf for Unbounded, Manrope, JetBrains Mono
```

Each `Features/<X>/` folder holds that tab's `View` + any tab-local subviews. No feature folder imports another feature folder directly — cross-feature data flows only through `AppStore`.

## 4. Navigation

`TabView` with six tabs (Heute, Voten, Reveal, Rangliste, Chat, Battle), each tab root wrapped in its own `NavigationStack` so push navigation (e.g. submission detail, chat thread) stays scoped per tab and doesn't affect the others — standard iOS tab-bar behavior, matching how the prototype's tabs are independent panels.

Group switching (prototype's `groupSwitcher` pill row) is a toolbar-level control available from every tab, calling `AppStore.selectGroup(_:)`; it does not reset the per-tab navigation stacks.

## 5. Error handling & testing

- All repository methods are `async throws`. `AppStore` methods catch and surface failures as a `@Observable var lastError: TodAppError?` that Views can bind to a `.alert`.
- `TodAppError` is a small enum (`.notFound`, `.alreadyVoted`, `.network(underlying: Error)`) — no stringly-typed errors.
- `InMemoryRepository` is the seam for testing: unit tests inject a `MockGroupRepository`/etc. (each a trivial struct closure-backed fake) into `AppStore` and assert on `AppStore` state transitions, never on UI.
- Voting invariants (one rating per submission per voter, one hidden-gem per voter per round, can't vote twice after `submitVotes`) are enforced inside `VoteRepository`/`InMemoryRepository`, not in Views — so the same rule holds regardless of which repository implementation is swapped in later.

## Deferred (not blocking this spec)

- Real audio playback for the waveform picker — prototype's waveform is a pure CSS/JS drag gesture with no audio decoding (see `brand-spec.md` reference), so v1 SwiftUI is the same: gesture-only, cosmetic playhead, no `AVAudioPlayer`.
- Push notifications, real backend/networking — `InMemoryRepository` is intentionally the only implementation for v1.
