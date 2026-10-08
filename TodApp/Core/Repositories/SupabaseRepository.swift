import Foundation
import Supabase
import os

/// The app's data on the Supabase project, behind the same protocols as
/// `InMemoryRepository`.
///
/// Thin on purpose: it asks and writes, and hands the rows to the pure types
/// beside it -- `GroupAssembly` builds the groups, `ScoreTally` adds up a
/// round, `BackendError` says what a refusal means. What a person may see or
/// change is decided on the server by row level security; the ids the
/// protocols pass along for the in-memory data are not trusted here, the
/// signed-in session is.
actor SupabaseRepository: GroupRepository, SubmissionRepository, VoteRepository,
                          ChatRepository, BattleRepository, ProfileRepository {
    private let client: SupabaseClient

    /// Downloaded pictures by bucket and path. A new picture gets a new path,
    /// so an entry never goes stale.
    private var pictures: [String: Data] = [:]
    /// The database's day for each post seen, needed to write a vote or gem.
    private var roundDays: [Int: String] = [:]

    /// PostgREST hands out at most this many rows at once (the project's
    /// default `max_rows`), so longer lists are read page by page.
    private static let pageSize = 1000
    private static let chatLimit = 200

    private static let groupColumns =
        "id,name,icon,image_path,creator_id,invite_policy,group_members(user_id,profiles(name,avatar_path))"
    private static let submissionColumns =
        "id,group_id,poster_id,track,artist,service,service_track_id,page_url,artwork_url,"
        + "duration_seconds,isrc,apple_music_id,section_start,section_end,posted_at,round_day,"
        + "comments(id,author_id,body,created_at)"
    private static let chatColumns = "id,group_id,author_id,body,mentioned_submission_id,created_at"
    private static let voteColumns = "submission_id,group_id,round_day,voter_id,rating,note"
    private static let gemColumns = "voter_id,group_id,round_day,submission_id"

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "backend")

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: Plumbing

    /// The signed-in user, as the database writes it.
    private func me() throws -> String {
        guard let user = client.auth.currentUser else { throw TodAppError.accountSignInFailed }
        return user.id.uuidString.lowercased()
    }

    @discardableResult
    private func attempt<T>(_ context: BackendError.Context, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            if !(error is CancellationError) {
                Self.log.error("\(String(describing: context), privacy: .public): \(String(describing: error), privacy: .public)")
            }
            throw BackendError.map(error, context: context)
        }
    }

    /// Every row, a page at a time. `fetch` gets the first and last index of
    /// the page it is to return.
    private func allPages<Row>(_ fetch: (Int, Int) async throws -> [Row]) async throws -> [Row] {
        var rows: [Row] = []
        var start = 0
        while true {
            let page = try await fetch(start, start + Self.pageSize - 1)
            rows += page
            guard page.count == Self.pageSize else { return rows }
            start += Self.pageSize
        }
    }

    private struct IDRecord: Decodable {
        let id: Int
    }

    private struct GroupIDRecord: Decodable {
        let id: String
    }

    private struct RoundDayRecord: Decodable {
        let roundDay: String
        private enum CodingKeys: String, CodingKey { case roundDay = "round_day" }
    }

    private struct PathRecord: Decodable {
        let path: String?
        private enum CodingKeys: String, CodingKey { case path }
    }

    // MARK: Pictures

    private func picture(in bucket: String, at path: String) async -> Data? {
        let key = "\(bucket)/\(path)"
        if let cached = pictures[key] { return cached }
        do {
            let data = try await client.storage.from(bucket).download(path: path)
            pictures[key] = data
            return data
        } catch {
            // A missing picture is not worth failing a list over; the emoji
            // or the initials stand in.
            Self.log.error("picture \(key, privacy: .private): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Shrinks and uploads a picture under a new name in `folder`, and returns
    /// its path.
    private func upload(_ imageData: Data, to bucket: String, folder: String) async throws -> String {
        guard let jpeg = ImageDownscale.jpeg(from: imageData) else { throw TodAppError.imageUnreadable }
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from(bucket).upload(
            path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        pictures["\(bucket)/\(path)"] = jpeg
        return path
    }

    /// The picture a new one replaced. Best effort: a leftover file costs a
    /// little space, not correctness.
    private func removeQuietly(_ path: String?, from bucket: String) async {
        guard let path else { return }
        do {
            _ = try await client.storage.from(bucket).remove(paths: [path])
        } catch {
            Self.log.error("old picture kept: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: GroupRepository

    func fetchGroups() async throws -> [Group] {
        try await attempt(.read) {
            let rows: [GroupRecord] = try await client.from("groups")
                .select(Self.groupColumns)
                .order("name")
                .execute().value
            return try await assemble(rows)
        }
    }

    /// The groups in `rows` with their posts, chat and pictures. The chat and
    /// the pictures of each group are read side by side rather than one after
    /// another.
    private func assemble(_ rows: [GroupRecord]) async throws -> [Group] {
        let me = try me()
        guard !rows.isEmpty else { return [] }
        let ids = rows.map(\.id)

        async let posts = submissions(in: ids)
        async let messages = messages(in: ids)
        async let images = pictures(at: rows.compactMap(\.imagePath))
        let (postRows, messageRows, imageData) = try await (posts, messages, images)
        for post in postRows { roundDays[post.id] = post.roundDay }

        return GroupAssembly.groups(
            from: rows, submissions: postRows, messages: messageRows, images: imageData,
            me: me, now: Date())
    }

    /// The groups' pictures, fetched side by side; the cache first.
    private func pictures(at paths: [String]) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for path in paths {
                group.addTask { (path, await self.picture(in: "group-images", at: path)) }
            }
            var found: [String: Data] = [:]
            for await (path, data) in group {
                if let data { found[path] = data }
            }
            return found
        }
    }

    private func submissions(in groupIDs: [String]) async throws -> [SubmissionRecord] {
        try await allPages { first, last in
            try await client.from("submissions")
                .select(Self.submissionColumns)
                .in("group_id", values: groupIDs)
                .order("posted_at")
                .order("id")
                .range(from: first, to: last)
                .execute().value
        }
    }

    /// The latest messages of each group, one request per group so a busy
    /// group cannot crowd out a quiet one -- sent side by side.
    private func messages(in groupIDs: [String]) async throws -> [ChatRecord] {
        try await withThrowingTaskGroup(of: [ChatRecord].self) { group in
            for id in groupIDs {
                group.addTask { try await self.messageRows(groupID: id) }
            }
            var all: [ChatRecord] = []
            for try await rows in group { all += rows }
            return all
        }
    }

    nonisolated private func messageRows(groupID: String) async throws -> [ChatRecord] {
        try await client.from("chat_messages")
            .select(Self.chatColumns)
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .limit(Self.chatLimit)
            .execute().value
    }

    /// The one group -- read on its own, not picked out of all of them.
    func fetchGroup(id: String) async throws -> Group {
        try await attempt(.read) {
            let rows: [GroupRecord] = try await client.from("groups")
                .select(Self.groupColumns)
                .eq("id", value: id)
                .execute().value
            guard let group = try await assemble(rows).first else { throw TodAppError.notFound }
            return group
        }
    }

    func updateGroup(id: String, name: String?, imageData: Data?, invitePolicy: InvitePolicy?) async throws {
        try await attempt(.write) {
            let newName = name.flatMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? nil : BackendRecords.clipped(trimmed, to: NewGroupDraft.maximumNameLength)
            }
            guard newName != nil || imageData != nil || invitePolicy != nil else { return }
            var newPath: String?
            var oldPath: String?
            if let imageData {
                let current: [PathRecord] = try await client.from("groups")
                    .select("path:image_path")
                    .eq("id", value: id)
                    .execute().value
                oldPath = current.first?.path
                newPath = try await upload(imageData, to: "group-images", folder: id)
            }
            let patch = GroupPatch(name: newName, invitePolicy: invitePolicy, imagePath: newPath)
            let updated: [GroupIDRecord] = try await client.from("groups")
                .update(patch)
                .eq("id", value: id)
                .select("id")
                .execute().value
            guard !updated.isEmpty else { throw TodAppError.notFound }
            if newPath != nil { await removeQuietly(oldPath, from: "group-images") }
        }
    }

    func createGroup(name: String, icon: String, asking userID: String) async throws -> String {
        try await attempt(.write) {
            let row: GroupIDRecord = try await client.from("groups")
                .insert(NewGroupPayload(name: name, icon: icon))
                .select("id")
                .single()
                .execute().value
            return row.id.lowercased()
        }
    }

    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite {
        try await attempt(.write) {
            let row: InviteRecord = try await client.from("group_invites")
                .insert(NewInvitePayload(groupID: groupID))
                .select("code,group_id,expires_at")
                .single()
                .execute().value
            return row.invite
        }
    }

    func joinGroup(code: String, asking userID: String) async throws -> String {
        try await attempt(.join) {
            let id: String = try await client
                .rpc("join_group", params: ["invite_code": InviteCode.normalized(code)])
                .execute().value
            return id.lowercased()
        }
    }

    /// Row level security turns a delete it does not allow into one that
    /// finds nothing, not into an error -- so each delete asks for the ids it
    /// removed, and none means "not yours to remove".
    private func deleted<T: Decodable>(_ rows: [T], refusing refusal: TodAppError = .notAllowed) throws {
        if rows.isEmpty { throw refusal }
    }

    private struct MemberRecord: Decodable {
        let userID: String
        private enum CodingKeys: String, CodingKey { case userID = "user_id" }
    }

    func leaveGroup(id: String, asking userID: String) async throws {
        try await attempt(.write) {
            let me = try me()
            let rows: [MemberRecord] = try await client.from("group_members")
                .delete()
                .eq("group_id", value: id)
                .eq("user_id", value: me)
                .select("user_id")
                .execute().value
            try deleted(rows, refusing: .notFound)
        }
    }

    func removeMember(_ memberID: String, from groupID: String, asking userID: String) async throws {
        try await attempt(.write) {
            let rows: [MemberRecord] = try await client.from("group_members")
                .delete()
                .eq("group_id", value: groupID)
                .eq("user_id", value: memberID.lowercased())
                .select("user_id")
                .execute().value
            try deleted(rows)
        }
    }

    /// Posts, votes, gems, comments, chat and invites go with the group
    /// (`on delete cascade`). Its picture is removed first, while the asker
    /// is still a member the storage policy lets remove it; a delete that
    /// then fails leaves the emoji standing in, which is the lesser harm
    /// than a file nobody can reach any more.
    func deleteGroup(id: String, asking userID: String) async throws {
        try await attempt(.write) {
            let current: [PathRecord] = try await client.from("groups")
                .select("path:image_path")
                .eq("id", value: id)
                .execute().value
            await removeQuietly(current.first?.path, from: "group-images")
            let rows: [GroupIDRecord] = try await client.from("groups")
                .delete()
                .eq("id", value: id)
                .select("id")
                .execute().value
            try deleted(rows)
        }
    }

    // MARK: SubmissionRepository

    /// The submission's own id and time are the server's; only what was
    /// posted goes up.
    func submit(_ submission: Submission, to groupID: String) async throws {
        try await attempt(.post) {
            try await client.from("submissions")
                .insert(NewSubmissionPayload(submission: submission, groupID: groupID), returning: .minimal)
                .execute()
        }
    }

    func addComment(
        _ text: String, authorID: String, authorName: String, submissionID: Int, groupID: String
    ) async throws {
        try await attempt(.write) {
            try await client.from("comments")
                .insert(
                    NewCommentPayload(submissionID: submissionID, groupID: groupID, body: text),
                    returning: .minimal)
                .execute()
        }
    }

    /// Its votes, gems and comments go with it; a chat message pointing at
    /// it stays, without the pointer. Nothing removed means the round has
    /// turned since the post was offered for deletion.
    func deleteSubmission(id: Int, groupID: String, asking userID: String) async throws {
        try await attempt(.write) {
            let rows: [IDRecord] = try await client.from("submissions")
                .delete()
                .eq("id", value: id)
                .eq("group_id", value: groupID)
                .select("id")
                .execute().value
            try deleted(rows, refusing: .roundClosed)
            roundDays[id] = nil
        }
    }

    func deleteComment(id: Int, submissionID: Int, groupID: String, asking userID: String) async throws {
        try await attempt(.write) {
            let rows: [IDRecord] = try await client.from("comments")
                .delete()
                .eq("id", value: id)
                .select("id")
                .execute().value
            try deleted(rows)
        }
    }

    // MARK: VoteRepository

    /// The database's day for a post, from the last load or, failing that,
    /// from the post itself.
    private func roundDay(of submissionID: Int) async throws -> String {
        if let known = roundDays[submissionID] { return known }
        let row: RoundDayRecord = try await client.from("submissions")
            .select("round_day")
            .eq("id", value: submissionID)
            .single()
            .execute().value
        roundDays[submissionID] = row.roundDay
        return row.roundDay
    }

    /// Changes the rating if there is one, adds it if not. Not an upsert:
    /// that would rewrite the song and day columns, which may not change.
    /// After midnight the update finds nothing and the insert is refused --
    /// which is what "the round is over" looks like from here.
    func castVote(_ vote: Vote, groupID: String) async throws {
        try await attempt(.vote) {
            let me = try me()
            let day = try await roundDay(of: vote.submissionID)
            let changed: [VoteRecord] = try await client.from("votes")
                .update(VotePatch(rating: vote.rating.rawValue, note: vote.note))
                .eq("submission_id", value: vote.submissionID)
                .eq("voter_id", value: me)
                .select(Self.voteColumns)
                .execute().value
            guard changed.isEmpty else { return }
            try await client.from("votes")
                .insert(NewVotePayload(vote: vote, groupID: groupID, roundDay: day), returning: .minimal)
                .execute()
        }
    }

    /// One gem per person, group and day: tapping the gem again takes it
    /// back, tapping another moves it.
    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
        try await attempt(.vote) {
            let me = try me()
            let day = try await roundDay(of: submissionID)
            let current: [GemRecord] = try await client.from("hidden_gems")
                .select(Self.gemColumns)
                .eq("voter_id", value: me)
                .eq("group_id", value: groupID)
                .eq("round_day", value: day)
                .execute().value

            if let gem = current.first {
                let mine = client.from("hidden_gems")
                if gem.submissionID == submissionID {
                    try await mine.delete(returning: .minimal)
                        .eq("voter_id", value: me)
                        .eq("group_id", value: groupID)
                        .eq("round_day", value: day)
                        .execute()
                } else {
                    try await mine.update(GemPatch(submissionID: submissionID), returning: .minimal)
                        .eq("voter_id", value: me)
                        .eq("group_id", value: groupID)
                        .eq("round_day", value: day)
                        .execute()
                }
            } else {
                try await client.from("hidden_gems")
                    .insert(
                        NewGemPayload(groupID: groupID, roundDay: day, submissionID: submissionID),
                        returning: .minimal)
                    .execute()
            }
        }
    }

    func fetchMyVotes(voterID: String, groupID: String, day: Date) async throws -> MyVotes {
        try await attempt(.read) {
            let me = try me()
            let roundDay = RoundDay.berlin(day)
            let votes: [VoteRecord] = try await client.from("votes")
                .select(Self.voteColumns)
                .eq("voter_id", value: me)
                .eq("group_id", value: groupID)
                .eq("round_day", value: roundDay)
                .execute().value
            let gems: [GemRecord] = try await client.from("hidden_gems")
                .select(Self.gemColumns)
                .eq("voter_id", value: me)
                .eq("group_id", value: groupID)
                .eq("round_day", value: roundDay)
                .execute().value

            var mine = MyVotes()
            for vote in votes.compactMap(\.vote) {
                mine.ratings[vote.submissionID] = vote.rating
                if let note = vote.note, !note.isEmpty { mine.notes[vote.submissionID] = note }
            }
            mine.hiddenGemID = gems.first?.submissionID
            return mine
        }
    }

    func fetchRoundScores(groupID: String, day: Date) async throws -> [RoundScore] {
        try await attempt(.read) {
            let roundDay = RoundDay.berlin(day)
            return try await scores(groupID: groupID) { $0.eq("round_day", value: roundDay) }
        }
    }

    func fetchVotes(groupID: String, day: Date) async throws -> [Vote] {
        try await attempt(.read) {
            let roundDay = RoundDay.berlin(day)
            return try await votes(groupID: groupID) { $0.eq("round_day", value: roundDay) }
                .compactMap(\.vote)
        }
    }

    /// Every day before today. The server shows nobody else's votes for today
    /// anyway; leaving today out keeps this user's own out of the season too.
    func fetchRevealedScores(groupID: String) async throws -> [RoundScore] {
        try await attempt(.read) {
            let today = RoundDay.berlin(Date())
            return try await scores(groupID: groupID) { $0.lt("round_day", value: today) }
        }
    }

    private typealias DayFilter = @Sendable (PostgrestFilterBuilder) -> PostgrestFilterBuilder

    private func scores(groupID: String, days: DayFilter) async throws -> [RoundScore] {
        let posts: [IDRecord] = try await allPages { first, last in
            try await days(client.from("submissions").select("id").eq("group_id", value: groupID))
                .order("posted_at")
                .order("id")
                .range(from: first, to: last)
                .execute().value
        }
        let votes = try await votes(groupID: groupID, days: days)
        let gems: [GemRecord] = try await allPages { first, last in
            try await days(client.from("hidden_gems").select(Self.gemColumns).eq("group_id", value: groupID))
                .order("round_day")
                .order("voter_id")
                .range(from: first, to: last)
                .execute().value
        }
        return ScoreTally.scores(submissionIDs: posts.map(\.id), votes: votes, gems: gems)
    }

    private func votes(groupID: String, days: DayFilter) async throws -> [VoteRecord] {
        try await allPages { first, last in
            try await days(client.from("votes").select(Self.voteColumns).eq("group_id", value: groupID))
                .order("submission_id")
                .order("voter_id")
                .range(from: first, to: last)
                .execute().value
        }
    }

    // MARK: ChatRepository

    func sendMessage(_ message: ChatMessage, groupID: String) async throws {
        try await attempt(.write) {
            try await client.from("chat_messages")
                .insert(NewChatPayload(message: message, groupID: groupID), returning: .minimal)
                .execute()
        }
    }

    func deleteMessage(id: UUID, groupID: String, asking userID: String) async throws {
        try await attempt(.write) {
            let rows: [GroupIDRecord] = try await client.from("chat_messages")
                .delete()
                .eq("id", value: id.uuidString.lowercased())
                .select("id")
                .execute().value
            try deleted(rows)
        }
    }

    /// The group's chat alone: its members for the names, and its messages.
    /// No posts, no comments, no pictures -- this is what every new message
    /// in an open chat reads.
    func fetchMessages(groupID: String) async throws -> [ChatMessage] {
        try await attempt(.read) {
            let me = try me()
            async let rows: [GroupRecord] = client.from("groups")
                .select(Self.groupColumns)
                .eq("id", value: groupID)
                .execute().value
            async let messages = messageRows(groupID: groupID)
            let (groupRows, messageRows) = try await (rows, messages)
            guard let group = GroupAssembly.groups(
                from: groupRows, submissions: [], messages: messageRows, images: [:],
                me: me, now: Date()).first
            else { throw TodAppError.notFound }
            return group.chatMessages
        }
    }

    /// Supabase Realtime: every new row in this group's `chat_messages`,
    /// `submissions` and `comments` (all three in the `supabase_realtime`
    /// publication; row level security still decides who hears of a row).
    /// The channel goes when the listening stops.
    nonisolated func groupActivity(groupID: String) -> AsyncStream<GroupActivity> {
        let client = client
        let channel = client.channel("group-\(groupID)")
        // Each table with what it is and the column naming who wrote the row.
        let tables: [(kind: GroupActivity.Kind, author: String, table: String)] = [
            (.chat, "author_id", "chat_messages"),
            (.post, "poster_id", "submissions"),
            (.comment, "author_id", "comments"),
        ]
        let streams = tables.map { entry in
            (entry.kind, entry.author,
             channel.postgresChange(InsertAction.self, table: entry.table, filter: .eq("group_id", value: groupID)))
        }
        return AsyncStream { continuation in
            let listening = Task {
                do {
                    try await channel.subscribeWithError()
                } catch {
                    Self.log.error("group realtime refused: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                    return
                }
                Self.log.notice("group realtime listening")
                await withTaskGroup(of: Void.self) { group in
                    for (kind, author, inserts) in streams {
                        group.addTask {
                            for await insert in inserts {
                                continuation.yield(GroupActivity(
                                    kind: kind,
                                    authorID: insert.record[author]?.stringValue?.lowercased()))
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                listening.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }

    // MARK: BattleRepository

    /// Battles have no table yet.
    func startBattle(_ battle: Battle, groupID: String) async throws {
        throw TodAppError.notAllowed
    }

    func fetchActiveBattle(groupID: String) async throws -> Battle? {
        nil
    }

    // MARK: ProfileRepository

    func fetchProfile(userID: String) async throws -> UserProfile {
        try await attempt(.read) {
            let row: ProfileRecord = try await client.from("profiles")
                .select("id,name,avatar_path,is_premium")
                .eq("id", value: userID)
                .single()
                .execute().value
            var imageData: Data?
            if let path = row.avatarPath {
                imageData = await picture(in: "avatars", at: path)
            }
            return UserProfile(
                id: row.id ?? userID, name: row.name, imageData: imageData,
                isPremium: row.isPremium ?? false)
        }
    }

    func updateProfile(userID: String, name: String?, imageData: Data?) async throws {
        try await attempt(.write) {
            let newName = name.flatMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : BackendRecords.clipped(trimmed, to: NewGroupDraft.maximumNameLength)
            }
            var newPath: String?
            var oldPath: String?
            if let imageData {
                let current: [PathRecord] = try await client.from("profiles")
                    .select("path:avatar_path")
                    .eq("id", value: userID)
                    .execute().value
                oldPath = current.first?.path
                newPath = try await upload(imageData, to: "avatars", folder: userID)
            }
            guard newName != nil || newPath != nil else { return }
            let updated: [ProfileRecord] = try await client.from("profiles")
                .update(ProfilePatch(name: newName, avatarPath: newPath))
                .eq("id", value: userID)
                .select("id,name,avatar_path,is_premium")
                .execute().value
            guard !updated.isEmpty else { throw TodAppError.notFound }
            if newPath != nil { await removeQuietly(oldPath, from: "avatars") }
        }
    }
}
