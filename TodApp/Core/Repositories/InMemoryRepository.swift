import Foundation

/// The repositories kept in memory, seeded with the two demo groups from
/// `tod-prototype.html` (`lnc`, `wg`). A build without a backend runs on this,
/// and so do the tests and previews; `SupabaseRepository` conforms to the same
/// protocols.
actor InMemoryRepository: GroupRepository, SubmissionRepository, VoteRepository,
                           ChatRepository, BattleRepository, ProfileRepository {

    static let shared = InMemoryRepository()

    /// Gluing ids into one string with "-" made two different things collide:
    /// "\(voterID)-\(groupID)" cannot say where the voter ends and the group
    /// begins, and reading a round back with `hasSuffix("-\(groupID)")` matched
    /// every group whose id happened to end that way. Struct keys carry the
    /// same three fields without the ambiguity.
    /// One hidden gem per voter per round -- and a round is a day, so the day
    /// belongs in the key. Without it, marking a gem today silently moves the
    /// one set yesterday, rewriting a round whose scores everyone has seen.
    private struct GemKey: Hashable {
        let voterID: String
        let groupID: String
        let roundDay: Date
    }

    private struct VoteKey: Hashable {
        let voterID: String
        let submissionID: Int
        let groupID: String
    }

    private var groups: [String: Group]
    private var votes: [VoteKey: Vote] = [:]
    private var hiddenGemByVoter: [GemKey: Int] = [:]
    private var invites: [String: GroupInvite] = [:]
    /// The one local person, the same one `LocalAccountService` signs in.
    private var profile = UserProfile(id: LocalAccountService.user.id, name: "Du", imageData: nil)

    init() {
        groups = InMemoryRepository.seedGroups()
        votes = InMemoryRepository.seedVotes()
        hiddenGemByVoter = InMemoryRepository.seedHiddenGems()
    }

    /// A round is identified by its day, so every key and comparison uses the
    /// start of that day rather than the instant a song happened to go up.
    private static func day(of date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // MARK: GroupRepository

    func fetchGroups() async throws -> [Group] {
        Array(groups.values).sorted { $0.name < $1.name }
    }

    func fetchGroup(id: String) async throws -> Group {
        guard let group = groups[id] else { throw TodAppError.notFound }
        return group
    }

    func updateGroup(
        id: String,
        name: String,
        imageData: Data?,
        invitePolicy: InvitePolicy
    ) async throws {
        guard var group = groups[id] else { throw TodAppError.notFound }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { group.name = trimmed }
        if let imageData { group.imageData = imageData }
        group.invitePolicy = invitePolicy
        groups[id] = group
    }

    func createGroup(name: String, icon: String, asking userID: String) async throws -> String {
        let id = UUID().uuidString.lowercased()
        let now = Date()
        let calendar = Calendar.current
        groups[id] = Group(
            id: id,
            name: name,
            icon: icon,
            members: [
                Member(
                    id: userID, name: userID == profile.id ? profile.name : userID,
                    isCurrentUser: true, postedDates: [])
            ],
            roundEndsAt: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now,
            submissions: [],
            chatMessages: [],
            activeBattle: nil,
            creatorID: userID,
            invitePolicy: .everyone
        )
        return id
    }

    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        guard GroupPermissions.mayInvite(userID, to: group) else { throw TodAppError.notAllowed }
        let invite = GroupInvite(
            code: InviteCode.random(), groupID: groupID,
            expiresAt: Date().addingTimeInterval(GroupInvite.lifetime))
        invites[invite.code] = invite
        return invite
    }

    func joinGroup(code: String, asking userID: String) async throws -> String {
        guard let invite = invites[InviteCode.normalized(code)], invite.expiresAt > Date(),
              var group = groups[invite.groupID]
        else { throw TodAppError.inviteInvalid }
        if !group.members.contains(where: { $0.id == userID }) {
            // Whoever joins here is the person holding the phone -- the only
            // one this data has.
            group.members.append(
                Member(id: userID, name: userID == profile.id ? profile.name : userID,
                       isCurrentUser: true, postedDates: []))
            groups[invite.groupID] = group
        }
        return invite.groupID
    }

    // MARK: ProfileRepository

    func fetchProfile(userID: String) async throws -> UserProfile {
        guard userID == profile.id else { throw TodAppError.notFound }
        return profile
    }

    func updateProfile(userID: String, name: String?, imageData: Data?) async throws {
        guard userID == profile.id else { throw TodAppError.notFound }
        if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            profile.name = trimmed
        }
        if let imageData { profile.imageData = imageData }
    }

    // MARK: SubmissionRepository

    func submit(_ submission: Submission, to groupID: String) async throws {
        guard groups[groupID] != nil else { throw TodAppError.notFound }
        groups[groupID]?.submissions.append(submission)
        if let i = groups[groupID]?.members.firstIndex(where: { $0.id == submission.posterID }) {
            // The post's own time rather than "now": the member's day is the
            // day the song went up, and whether they posted today follows from it.
            groups[groupID]?.members[i].postedDates.append(submission.postedAt)
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
        _ = try runningSubmission(vote.submissionID, in: groupID)
        votes[VoteKey(voterID: vote.voterID, submissionID: vote.submissionID, groupID: groupID)] = vote
    }

    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
        let submission = try runningSubmission(submissionID, in: groupID)
        let key = GemKey(
            voterID: voterID, groupID: groupID, roundDay: Self.day(of: submission.postedAt))
        hiddenGemByVoter[key] = (hiddenGemByVoter[key] == submissionID) ? nil : submissionID
    }

    /// The rule enforced below the views as well as above them: a round whose
    /// day is over takes no more votes, however the caller got here. `AppStore`
    /// stops offering the buttons; this stops the write.
    private func runningSubmission(_ submissionID: Int, in groupID: String) throws -> Submission {
        guard let group = groups[groupID],
              let submission = group.submissions.first(where: { $0.id == submissionID })
        else { throw TodAppError.notFound }
        guard RoundVisibility.isVotable(roundDay: submission.postedAt) else {
            throw TodAppError.roundClosed
        }
        return submission
    }

    private func submissionIDs(in group: Group, on day: Date) -> [Int] {
        let calendar = Calendar.current
        return group.submissions
            .filter { calendar.isDate($0.postedAt, inSameDayAs: day) }
            .map(\.id)
    }

    func fetchMyVotes(voterID: String, groupID: String, day: Date) async throws -> MyVotes {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        // Only this round's ratings: a rating carries no day of its own, so
        // without narrowing to the round's songs an old vote would show up on
        // a screen that is asking about today.
        let round = Set(submissionIDs(in: group, on: day))
        var ratings: [Int: Rating] = [:]
        for (key, vote) in votes
        where key.voterID == voterID && key.groupID == groupID && round.contains(key.submissionID) {
            ratings[key.submissionID] = vote.rating
        }
        var notes: [Int: String] = [:]
        for (key, vote) in votes
        where key.voterID == voterID && key.groupID == groupID && round.contains(key.submissionID) {
            if let note = vote.note, !note.isEmpty { notes[key.submissionID] = note }
        }
        return MyVotes(
            ratings: ratings,
            notes: notes,
            hiddenGemID: hiddenGemByVoter[
                GemKey(voterID: voterID, groupID: groupID, roundDay: Self.day(of: day))]
        )
    }

    func fetchVotes(groupID: String, day: Date) async throws -> [Vote] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        let round = Set(submissionIDs(in: group, on: day))
        return votes
            .filter { $0.key.groupID == groupID && round.contains($0.key.submissionID) }
            .map(\.value)
    }

    func fetchRoundScores(groupID: String, day: Date) async throws -> [RoundScore] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        let roundDay = Self.day(of: day)
        let groupVotes = votes.filter { $0.key.groupID == groupID }.values
        // Every submission of that day appears, even unrated ones -- a song
        // nobody voted on scored zero, which is different from not being in the
        // round. Whether the day may be shown at all is `RoundVisibility`'s
        // decision, made by the caller; here a day is just a day.
        return submissionIDs(in: group, on: day).map { submissionID in
            let points = groupVotes
                .filter { $0.submissionID == submissionID }
                .reduce(0) { $0 + $1.rating.rawValue }
            let gems = hiddenGemByVoter
                .filter {
                    $0.key.groupID == groupID && $0.key.roundDay == roundDay
                        && $0.value == submissionID
                }
                .count
            return RoundScore(submissionID: submissionID, points: points, hiddenGemCount: gems)
        }
    }

    /// Every day that is over, scored. Built from the submissions themselves
    /// rather than a list of days kept somewhere: a round exists because songs
    /// were posted on that day, and nowhere else.
    func fetchRevealedScores(groupID: String) async throws -> [RoundScore] {
        guard let group = groups[groupID] else { throw TodAppError.notFound }
        let days = Set(
            group.submissions
                .filter { RoundVisibility.isRevealed(roundDay: $0.postedAt) }
                .map { Self.day(of: $0.postedAt) }
        )
        var scores: [RoundScore] = []
        for day in days {
            scores += try await fetchRoundScores(groupID: groupID, day: day)
        }
        return scores
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

    /// A moment earlier today -- never yesterday, however late it is.
    ///
    /// The seed used to place today's songs at "N hours ago". Shortly after
    /// midnight that is yesterday, so the round they belong to changed under
    /// them: votes on them came back `.roundClosed` and the season table
    /// counted them as revealed. Anchored to the start of the day instead, the
    /// seed means the same thing at one in the morning as at noon.
    private static func earlierToday(_ minutesAgo: Double, from now: Date = Date()) -> Date {
        let dayStart = Calendar.current.startOfDay(for: now)
        return max(now.addingTimeInterval(-minutesAgo * 60), dayStart.addingTimeInterval(60))
    }

    /// Yesterday at a given hour, read off the calendar rather than counted
    /// back in hours: run at 01:00, "26 hours ago" lands two days back, and the
    /// revealed round -- which is yesterday exactly -- would come up empty.
    private static func yesterday(at hour: Int, from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    /// Yesterday's round already voted on, so Reveal opens on a real result
    /// instead of a table of zeroes. Today's round is deliberately left blank:
    /// that is the one the app is asking you to rate.
    private static func seedVotes() -> [VoteKey: Vote] {
        var votes: [VoteKey: Vote] = [:]
        func cast(
            _ voterID: String, _ submissionID: Int, _ rating: Rating,
            in groupID: String, note: String? = nil
        ) {
            votes[VoteKey(voterID: voterID, submissionID: submissionID, groupID: groupID)] =
                Vote(
                    voterID: voterID, submissionID: submissionID, rating: rating,
                    isHiddenGem: false, note: note
                )
        }

        // Late Night Crew: "Nights" takes the day at 5, "Kids" goes negative.
        cast("du", 8, .banger, in: "lnc")
        cast("lena", 8, .good, in: "lnc")
        cast("jaro", 8, .ok, in: "lnc")
        cast("finn", 8, .good, in: "lnc")

        cast("du", 9, .banger, in: "lnc", note: "die zweite Hälfte ist ein anderer Song")
        cast("mats", 9, .banger, in: "lnc")
        cast("jaro", 9, .good, in: "lnc")
        cast("finn", 9, .ok, in: "lnc")

        cast("du", 10, .meh, in: "lnc")
        cast("mats", 10, .ok, in: "lnc")
        cast("lena", 10, .good, in: "lnc")
        cast("finn", 10, .meh, in: "lnc", note: "hab ich zu oft gehört")

        // WG Chaos: "Da Funk" wins, "Bad Habit" lands exactly on zero -- which
        // is a score, not an absence, and Reveal has to show it as one.
        cast("du", 11, .good, in: "wg")
        cast("tim", 11, .banger, in: "wg", note: "lief bei mir den ganzen Abend")
        cast("bea", 11, .ok, in: "wg")

        cast("du", 12, .banger, in: "wg")
        cast("nora", 12, .good, in: "wg")
        cast("bea", 12, .good, in: "wg")

        cast("du", 13, .ok, in: "wg")
        cast("nora", 13, .meh, in: "wg")
        cast("tim", 13, .good, in: "wg")

        return votes
    }

    /// Filed under yesterday's day, so today's gem -- once someone sets one --
    /// cannot displace it.
    private static func seedHiddenGems() -> [GemKey: Int] {
        let roundDay = day(of: yesterday(at: 12))
        return [
            GemKey(voterID: "du", groupID: "lnc", roundDay: roundDay): 9,
            GemKey(voterID: "lena", groupID: "lnc", roundDay: roundDay): 8,
            GemKey(voterID: "du", groupID: "wg", roundDay: roundDay): 12,
        ]
    }

    /// A real, public Spotify track, so the demo data has something the player
    /// can actually play. "Blinding Lights" also carries a picked stretch from
    /// 1:00 -- without one, nothing in the demo shows whether the player starts
    /// where the poster chose. Both ids below were checked against Spotify's own
    /// oEmbed rather than typed from memory -- a wrong one looks exactly like
    /// a broken player.
    private static func spotify(_ id: String) -> TrackSource {
        TrackSource(
            service: .spotify,
            serviceTrackID: id,
            pageURL: URL(string: "https://open.spotify.com/track/\(id)")!,
            artworkURL: nil
        )
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
                Member(id: "du", name: "Du", isCurrentUser: true, postedDates: streakDates(endingDaysAgo: 1, count: 5, from: now)),
                Member(id: "mats", name: "Mats", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 0, count: 3, from: now)),
                Member(id: "lena", name: "Lena", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 0, count: 7, from: now)),
                Member(id: "jaro", name: "Jaro", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 0, count: 1, from: now)),
                // Never posted, so no streak at all.
                Member(id: "sude", name: "Sude", isCurrentUser: false, postedDates: []),
                Member(id: "finn", name: "Finn", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 1, count: 2, from: now)),
            ],
            roundEndsAt: now.addingTimeInterval(3 * 3600 + 41 * 60 + 12),
            submissions: [
                // Yesterday's round -- the one Reveal shows, with the votes
                // below already cast. Today's four are still running and
                // deliberately carry no scores yet.
                Submission(id: 8, posterID: "mats", track: "Redbone", artist: "Childish Gambino", coverColorHex: "#2f3a5c", comments: [], postedAt: yesterday(at: 20)),
                Submission(id: 9, posterID: "lena", track: "Nights", artist: "Frank Ocean", coverColorHex: "#5c3a2f", comments: [Comment(id: 1, authorID: "mats", authorName: "Mats", text: "der Beat-Switch, jedes Mal", postedAt: yesterday(at: 21))], postedAt: yesterday(at: 19)),
                Submission(id: 10, posterID: "jaro", track: "Kids", artist: "MGMT", coverColorHex: "#3a5c2f", comments: [], postedAt: yesterday(at: 22)),
                Submission(id: 1, posterID: "mats", track: "Blinding Lights", artist: "The Weeknd", coverColorHex: "#3a2a5c", comments: [Comment(id: 1, authorID: "lena", authorName: "Lena", text: "zu früh am Tag für den Banger, aber ok 🔥", postedAt: Date().addingTimeInterval(-7200))], source: spotify("0VjIjW4GlUZAMYd2vXMi3b"), section: TrackSection(start: 60, end: 90), postedAt: earlierToday(35)),
                Submission(id: 2, posterID: "lena", track: "Passionfruit", artist: "Drake", coverColorHex: "#5c2a3a", comments: [Comment(id: 1, authorID: "mats", authorName: "Mats", text: "DAS ist der Sieger, sorry", postedAt: earlierToday(90)), Comment(id: 2, authorID: "jaro", authorName: "Jaro", text: "wusste sofort wer das ist", postedAt: Date().addingTimeInterval(-3600))], postedAt: earlierToday(90)),
                Submission(id: 3, posterID: "jaro", track: "Sunflower", artist: "Post Malone, Swae Lee", coverColorHex: "#2a4a5c", comments: [], postedAt: earlierToday(30)),
                Submission(id: 4, posterID: "finn", track: "Electric Feel", artist: "MGMT", coverColorHex: "#4a5c2a", comments: [Comment(id: 1, authorID: "finn", authorName: "Finn", text: "interessante Wahl heute", postedAt: Date().addingTimeInterval(-4800))], postedAt: earlierToday(240)),
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
            ),
            // Lena's group, and she kept invites to herself -- so this is the
            // seeded case where "du" sees the setting and cannot move it.
            creatorID: "lena",
            invitePolicy: .creatorOnly
        )

        let wg = Group(
            id: "wg",
            name: "WG Chaos",
            icon: "🏠",
            members: [
                Member(id: "du", name: "Du", isCurrentUser: true, postedDates: streakDates(endingDaysAgo: 0, count: 5, from: now)),
                Member(id: "nora", name: "Nora", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 0, count: 4, from: now)),
                Member(id: "tim", name: "Tim", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 0, count: 9, from: now)),
                Member(id: "bea", name: "Bea", isCurrentUser: false, postedDates: streakDates(endingDaysAgo: 1, count: 1, from: now)),
            ],
            roundEndsAt: now.addingTimeInterval(1 * 3600 + 12 * 60 + 40),
            submissions: [
                // Yesterday's round, see above.
                Submission(id: 11, posterID: "nora", track: "Motion Sickness", artist: "Phoebe Bridgers", coverColorHex: "#4a2f5c", comments: [], postedAt: yesterday(at: 18)),
                Submission(id: 12, posterID: "tim", track: "Da Funk", artist: "Daft Punk", coverColorHex: "#2f5c4a", comments: [Comment(id: 1, authorID: "bea", authorName: "Bea", text: "das lief bei uns dreimal", postedAt: yesterday(at: 20))], postedAt: yesterday(at: 17)),
                Submission(id: 13, posterID: "bea", track: "Bad Habit", artist: "Steve Lacy", coverColorHex: "#5c5c2f", comments: [], postedAt: yesterday(at: 21)),
                Submission(id: 5, posterID: "nora", track: "As It Was", artist: "Harry Styles", coverColorHex: "#5c4a2a", comments: [Comment(id: 1, authorID: "jaro", authorName: "Jaro", text: "solide, aber erwartbar", postedAt: Date().addingTimeInterval(-6000))], source: spotify("4Dvkj6JhhA12EX05fT7y2e"), postedAt: earlierToday(55)),
                Submission(id: 6, posterID: "tim", track: "One More Time", artist: "Daft Punk", coverColorHex: "#2a5c4e", comments: [], postedAt: earlierToday(90)),
                Submission(id: 7, posterID: "du", track: "Genesis", artist: "Justice", coverColorHex: "#5c2a4e", comments: [Comment(id: 1, authorID: "lena", authorName: "Lena", text: "warte ist das dein Song??", postedAt: Date().addingTimeInterval(-2400))], postedAt: earlierToday(20)),
            ],
            chatMessages: [
                ChatMessage(id: UUID(), authorTag: "TI", authorName: "Tim", text: "wer räumt den Kühlschrank auf 💀", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "NO", authorName: "Nora", text: "nicht ich, aber guter Song heute", isFromCurrentUser: false),
                ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "danke danke", isFromCurrentUser: true),
            ],
            activeBattle: nil,
            // Your own group, open to everyone in it -- the other half of the
            // rule, so both states are visible without editing anything.
            creatorID: "du",
            invitePolicy: .everyone
        )

        return ["lnc": lnc, "wg": wg]
    }
}
