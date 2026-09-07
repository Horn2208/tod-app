import Foundation

/// Single in-memory implementation of all six repository protocols, seeded with
/// the two demo groups from `tod-prototype.html` (`lnc`, `wg`). This is the only
/// repository implementation for v1 — no backend. A future networked repository
/// can conform to the same six protocols without AppStore or any View changing.
actor InMemoryRepository: GroupRepository, SubmissionRepository, VoteRepository,
                           LeaderboardRepository, ChatRepository, BattleRepository {

    static let shared = InMemoryRepository()

    /// Gluing ids into one string with "-" made two different things collide:
    /// "\(voterID)-\(groupID)" cannot say where the voter ends and the group
    /// begins, and reading a round back with `hasSuffix("-\(groupID)")` matched
    /// every group whose id happened to end that way. Struct keys carry the
    /// same three fields without the ambiguity.
    private struct VoterKey: Hashable {
        let voterID: String
        let groupID: String
    }

    private struct VoteKey: Hashable {
        let voterID: String
        let submissionID: Int
        let groupID: String
    }

    private var groups: [String: Group]
    private var votes: [VoteKey: Vote] = [:]
    private var hiddenGemByVoter: [VoterKey: Int] = [:]
    private var submittedVoters: Set<VoterKey> = []

    init() {
        groups = InMemoryRepository.seedGroups()
    }

    // MARK: GroupRepository

    func fetchGroups() async throws -> [Group] {
        Array(groups.values).sorted { $0.name < $1.name }
    }

    func fetchGroup(id: String) async throws -> Group {
        guard let group = groups[id] else { throw TodAppError.notFound }
        return group
    }

    // MARK: SubmissionRepository

    func submit(_ submission: Submission, to groupID: String) async throws {
        guard groups[groupID] != nil else { throw TodAppError.notFound }
        groups[groupID]?.submissions.append(submission)
        if let i = groups[groupID]?.members.firstIndex(where: { $0.id == submission.posterID }) {
            groups[groupID]?.members[i].hasPostedToday = true
            groups[groupID]?.members[i].postedDates.append(Date())
        }
    }

    /// The caller passes text and who wrote it; the id is assigned here,
    /// where the existing comments are, the same way submission ids are.
    func addComment(
        _ text: String,
        authorID: String,
        authorName: String,
        submissionID: Int,
        groupID: String
    ) async throws {
        guard var group = groups[groupID],
              let index = group.submissions.firstIndex(where: { $0.id == submissionID }) else {
            throw TodAppError.notFound
        }
        let nextID = (group.submissions[index].comments.map(\.id).max() ?? 0) + 1
        group.submissions[index].comments.append(
            Comment(
                id: nextID, authorID: authorID, authorName: authorName,
                text: text, postedAt: Date()
            )
        )
        groups[groupID] = group
    }

    // MARK: VoteRepository

    func castVote(_ vote: Vote, groupID: String) async throws {
        let voterKey = VoterKey(voterID: vote.voterID, groupID: groupID)
        guard !submittedVoters.contains(voterKey) else { throw TodAppError.alreadyVoted }
        votes[VoteKey(voterID: vote.voterID, submissionID: vote.submissionID, groupID: groupID)] = vote
    }

    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
        let voterKey = VoterKey(voterID: voterID, groupID: groupID)
        guard !submittedVoters.contains(voterKey) else { throw TodAppError.alreadyVoted }
        hiddenGemByVoter[voterKey] = (hiddenGemByVoter[voterKey] == submissionID) ? nil : submissionID
    }

    func submitVotes(voterID: String, groupID: String) async throws {
        submittedVoters.insert(VoterKey(voterID: voterID, groupID: groupID))
    }

    func fetchMyVotes(voterID: String, groupID: String) async throws -> MyVotes {
        let voterKey = VoterKey(voterID: voterID, groupID: groupID)
        var ratings: [Int: Rating] = [:]
        for (key, vote) in votes where key.voterID == voterID && key.groupID == groupID {
            ratings[key.submissionID] = vote.rating
        }
        return MyVotes(
            ratings: ratings,
            hiddenGemID: hiddenGemByVoter[voterKey],
            hasSubmitted: submittedVoters.contains(voterKey)
        )
    }

    func fetchRoundScores(groupID: String) async throws -> [RoundScore] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        let groupVotes = votes.filter { $0.key.groupID == groupID }.values
        // Every submission appears, even unrated ones -- a song nobody voted on
        // scored zero, which is different from not being in the round.
        return group.submissions.map { submission in
            let points = groupVotes
                .filter { $0.submissionID == submission.id }
                .reduce(0) { $0 + $1.rating.rawValue }
            let gems = hiddenGemByVoter
                .filter { $0.key.groupID == groupID && $0.value == submission.id }
                .count
            return RoundScore(submissionID: submission.id, points: points, hiddenGemCount: gems)
        }
    }

    // MARK: LeaderboardRepository

    func fetchBoard(groupID: String) async throws -> [BoardEntry] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        return group.board.sorted { $0.points > $1.points }
    }

    // MARK: ChatRepository

    func sendMessage(_ message: ChatMessage, groupID: String) async throws {
        guard groups[groupID] != nil else { throw TodAppError.notFound }
        groups[groupID]?.chatMessages.append(message)
    }

    func fetchMessages(groupID: String) async throws -> [ChatMessage] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        return group.chatMessages
    }

    // MARK: BattleRepository

    func startBattle(_ battle: Battle, groupID: String) async throws {
        guard groups[groupID] != nil else { throw TodAppError.notFound }
        groups[groupID]?.activeBattle = battle
    }

    func fetchActiveBattle(groupID: String) async throws -> Battle? {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        return group.activeBattle
    }

    // MARK: Seed data — matches tod-prototype.html GROUPS object (source lines 773-846)

    /// Builds `count` consecutive daily posting dates ending `daysAgo` days
    /// before `now` (0 = today, 1 = yesterday) -- lets the seed express a
    /// member's streak length without hand-computing timestamps.
    private static func streakDates(endingDaysAgo daysAgo: Int, count: Int, from now: Date) -> [Date] {
        let calendar = Calendar.current
        guard count > 0 else { return [] }
        return (0..<count).map { offset in
            calendar.date(byAdding: .day, value: -(daysAgo + offset), to: now)!
        }
    }

    private static func seedGroups() -> [String: Group] {
        let now = Date()

        let lnc = Group(
            id: "lnc",
            name: "Late Night Crew",
            icon: "🌙",
            members: [
                // "Du" hasn't posted yet today in this group, so the streak's
                // dates end yesterday -- exactly the "day is not over" case.
                Member(id: "du", name: "Du", isCurrentUser: true, hasPostedToday: false, postedDates: streakDates(endingDaysAgo: 1, count: 5, from: now)),
                Member(id: "mats", name: "MA", isCurrentUser: false, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 3, from: now)),
                Member(id: "lena", name: "LE", isCurrentUser: false, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 7, from: now)),
                Member(id: "jaro", name: "JA", isCurrentUser: false, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 1, from: now)),
                // Never posted, so no streak at all.
                Member(id: "sude", name: "SU", isCurrentUser: false, hasPostedToday: false, postedDates: []),
                Member(id: "finn", name: "FI", isCurrentUser: false, hasPostedToday: false, postedDates: streakDates(endingDaysAgo: 1, count: 2, from: now)),
            ],
            roundEndsAt: now.addingTimeInterval(3 * 3600 + 41 * 60 + 12),
            submissions: [
                Submission(id: 1, posterID: "mats", track: "Blinding Lights", artist: "The Weeknd", coverColorHex: "#3a2a5c", comments: [Comment(id: 1, authorID: "lena", authorName: "Lena", text: "zu früh am Tag für den Banger, aber ok 🔥", postedAt: Date().addingTimeInterval(-7200))]),
                Submission(id: 2, posterID: "lena", track: "Passionfruit", artist: "Drake", coverColorHex: "#5c2a3a", comments: [Comment(id: 1, authorID: "mats", authorName: "Mats", text: "DAS ist der Sieger, sorry", postedAt: Date().addingTimeInterval(-5400)), Comment(id: 2, authorID: "jaro", authorName: "Jaro", text: "wusste sofort wer das ist", postedAt: Date().addingTimeInterval(-3600))]),
                Submission(id: 3, posterID: "jaro", track: "Sunflower", artist: "Post Malone, Swae Lee", coverColorHex: "#2a4a5c", comments: []),
                Submission(id: 4, posterID: "finn", track: "Electric Feel", artist: "MGMT", coverColorHex: "#4a5c2a", comments: [Comment(id: 1, authorID: "finn", authorName: "Finn", text: "interessante Wahl heute", postedAt: Date().addingTimeInterval(-4800))]),
            ],
            board: [
                BoardEntry(name: "Lena", tag: "LE", points: 210, subtitle: "6 Siege · 2 Battles · Quiz-Master Pop"),
                BoardEntry(name: "Mats", tag: "MA", points: 175, subtitle: "4 Siege · 3 Battles"),
                BoardEntry(name: "Du", tag: "DU", points: 140, subtitle: "3 Siege · 1 Battle · Quiz-Master EDM"),
                BoardEntry(name: "Jaro", tag: "JA", points: 95, subtitle: "2 Siege"),
                BoardEntry(name: "Finn", tag: "FI", points: 60, subtitle: "1 Sieg · Rätsel-Ass Hip-Hop"),
            ],
            chatMessages: [
                ChatMessage(id: UUID(), authorTag: "LE", authorName: "Lena", text: "Leute wer hat heute Passionfruit gepostet 😭", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "MA", authorName: "Mats", text: "kann ich beim Reveal ja nicht sagen", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "ich hab meins schon fertig ausgesucht", isFromCurrentUser: true),
                ChatMessage(id: UUID(), authorTag: "JA", authorName: "Jaro", text: "Battle heute Abend? 👀", isFromCurrentUser: false),
            ],
            activeBattle: Battle(
                mode: .artistDice,
                player1: BattleEntry(name: "Mats", track: "Bad Guy", artist: "Billie Eilish", coverColorHex: "#3a2a5c", percentage: 62),
                player2: BattleEntry(name: "Sude", track: "Ocean Eyes", artist: "Billie Eilish", coverColorHex: "#5c2a3a", percentage: 38),
                diceArtists: ["Billie Eilish", "Tame Impala", "Doja Cat", "ROSALÍA", "Travis Scott"]
            )
        )

        let wg = Group(
            id: "wg",
            name: "WG Chaos",
            icon: "🏠",
            members: [
                Member(id: "du", name: "Du", isCurrentUser: true, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 5, from: now)),
                Member(id: "nora", name: "NO", isCurrentUser: false, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 4, from: now)),
                Member(id: "tim", name: "TI", isCurrentUser: false, hasPostedToday: true, postedDates: streakDates(endingDaysAgo: 0, count: 9, from: now)),
                Member(id: "bea", name: "BE", isCurrentUser: false, hasPostedToday: false, postedDates: streakDates(endingDaysAgo: 1, count: 1, from: now)),
            ],
            roundEndsAt: now.addingTimeInterval(1 * 3600 + 12 * 60 + 40),
            submissions: [
                Submission(id: 5, posterID: "nora", track: "As It Was", artist: "Harry Styles", coverColorHex: "#5c4a2a", comments: [Comment(id: 1, authorID: "jaro", authorName: "Jaro", text: "solide, aber erwartbar", postedAt: Date().addingTimeInterval(-6000))]),
                Submission(id: 6, posterID: "tim", track: "One More Time", artist: "Daft Punk", coverColorHex: "#2a5c4e", comments: []),
                Submission(id: 7, posterID: "du", track: "Genesis", artist: "Justice", coverColorHex: "#5c2a4e", comments: [Comment(id: 1, authorID: "lena", authorName: "Lena", text: "warte ist das dein Song??", postedAt: Date().addingTimeInterval(-2400))]),
            ],
            board: [
                BoardEntry(name: "Tim", tag: "TI", points: 130, subtitle: "3 Siege · 1 Battle"),
                BoardEntry(name: "Du", tag: "DU", points: 110, subtitle: "2 Siege · Quiz-Master Hip-Hop"),
                BoardEntry(name: "Nora", tag: "NO", points: 85, subtitle: "2 Siege"),
                BoardEntry(name: "Bea", tag: "BE", points: 40, subtitle: "1 Sieg"),
            ],
            chatMessages: [
                ChatMessage(id: UUID(), authorTag: "TI", authorName: "Tim", text: "wer räumt den Kühlschrank auf 💀", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "NO", authorName: "Nora", text: "nicht ich, aber guter Song heute", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "danke danke", isFromCurrentUser: true),
            ],
            activeBattle: nil
        )

        return ["lnc": lnc, "wg": wg]
    }
}
