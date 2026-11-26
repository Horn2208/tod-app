import Foundation
import Testing
@testable import TodApp

/// Reporting and blocking (`docs/prompt.md`, item 15).
@Suite
struct ReportAndBlockRuleTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try BackendRecords.encoder.encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func aReportSendsWhatTheTableTakes() throws {
        let message = try #require(UUID(uuidString: "6F1C1D4E-0000-4000-8000-000000000001"))
        let body = try json(NewReportPayload(report: Report(
            groupID: "g1", target: .chatMessage(message), reportedUserID: "ABC",
            reason: .offensive, excerpt: "na du")))

        #expect(Set(body.keys) == [
            "group_id", "target_kind", "target_id", "reported_user_id", "reason", "excerpt"])
        #expect(body["target_kind"] as? String == "chat_message")
        #expect(body["target_id"] as? String == "6f1c1d4e-0000-4000-8000-000000000001")
        #expect(body["reported_user_id"] as? String == "abc")
        #expect(body["reason"] as? String == "offensive")
    }

    @Test
    func aPersonReportCarriesNoExcerpt() throws {
        let body = try json(NewReportPayload(report: Report(
            groupID: "g1", target: .member("lena"), reportedUserID: "lena",
            reason: .spam, excerpt: nil)))
        #expect(body["target_kind"] as? String == "member")
        #expect(body["excerpt"] == nil)
    }

    @Test
    func aLongExcerptIsCutToWhatTheTableAllows() {
        let report = Report(groupID: "g", target: .comment(3), reportedUserID: nil, reason: .other,
                            excerpt: String(repeating: "a", count: 900))
        #expect(report.excerpt?.count == Report.maximumExcerptLength)
        #expect(Report.Target.submission(12).id == "12")
    }

    @Test
    func hidingLeavesOutPostsCommentsAndMessagesButNotTheMember() {
        let lena = Member(id: "lena", name: "Lena", isCurrentUser: false, postedDates: [])
        let du = Member(id: "du", name: "Du", isCurrentUser: true, postedDates: [])
        let hers = Submission(id: 1, posterID: "lena", track: "A", artist: "X",
                              coverColorHex: "#000000", comments: [])
        let mine = Submission(
            id: 2, posterID: "du", track: "B", artist: "Y", coverColorHex: "#000000",
            comments: [
                Comment(id: 1, authorID: "lena", authorName: "Lena", text: "hm", postedAt: .now),
                Comment(id: 2, authorID: "mats", authorName: "Mats", text: "gut", postedAt: .now),
            ])
        let group = Group(
            id: "g", name: "G", icon: "🎵", members: [du, lena], roundEndsAt: .now,
            submissions: [hers, mine],
            chatMessages: [
                ChatMessage(id: UUID(), authorTag: "LE", authorName: "Lena", text: "hi",
                            isFromCurrentUser: false, authorID: "lena"),
                ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "hey",
                            isFromCurrentUser: true, authorID: "du"),
            ],
            activeBattle: nil)

        let seen = GroupAssembly.hiding(["lena"], in: group)

        #expect(seen.submissions.map(\.id) == [2])
        #expect(seen.submissions.first?.comments.map(\.authorID) == ["mats"])
        #expect(seen.chatMessages.map(\.text) == ["hey"])
        #expect(seen.members.map(\.id) == ["du", "lena"])
    }
}

@Suite
@MainActor
struct ReportAndBlockStoreTests {
    private func store(_ repo: InMemoryRepository) -> AppStore {
        AppStore(groupRepo: repo, submissionRepo: repo, voteRepo: repo, chatRepo: repo,
                 battleRepo: repo, profileRepo: repo, moderationRepo: repo)
    }

    private func posts(by userID: String, in store: AppStore) -> Int {
        store.groups.flatMap(\.submissions).filter { $0.posterID == userID }.count
    }

    @Test
    func blockingHidesSomeoneEverywhereAndUnblockingBringsThemBack() async {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let before = posts(by: "lena", in: store)
        #expect(before > 0)

        #expect(await store.block("lena"))
        #expect(store.isBlocked("lena"))
        #expect(posts(by: "lena", in: store) == 0)
        #expect(store.groups.contains { $0.members.contains { $0.id == "lena" } })

        #expect(await store.unblock("lena"))
        #expect(posts(by: "lena", in: store) == before)
    }

    @Test
    func nobodyBlocksThemselves() async {
        let store = store(InMemoryRepository())
        await store.loadGroups()
        let blocked = await store.block("du")
        #expect(!blocked)
        #expect(!store.mayReport("du"))
        #expect(store.mayReport("lena"))
    }

    @Test
    func aReportIsKept() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let groupID = try #require(store.groups.first?.id)
        let report = Report(groupID: groupID, target: .member("lena"), reportedUserID: "lena",
                            reason: .offensive, excerpt: nil)

        #expect(await store.report(report))

        #expect(await repo.reports == [report])
    }

    @Test
    func theBlockListComesBackWithTheGroups() async {
        let repo = InMemoryRepository()
        try? await repo.block("mats")
        let store = store(repo)
        await store.loadGroups()
        #expect(store.isBlocked("mats"))
    }
}
