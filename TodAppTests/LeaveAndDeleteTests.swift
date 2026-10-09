import Foundation
import Testing
@testable import TodApp

/// Leaving, removing and deleting (`docs/prompt.md`, item 14): the rules, the
/// in-memory repository that stands in for the server, and the store.
@Suite
struct LeaveAndDeleteRuleTests {
    private func member(_ id: String) -> Member {
        Member(id: id, name: id.capitalized, isCurrentUser: id == "du", postedDates: [])
    }

    private func group(members: [String], creator: String) -> Group {
        Group(
            id: "g", name: "WG", icon: "🏠", members: members.map(member), roundEndsAt: .now,
            submissions: [], chatMessages: [], activeBattle: nil, creatorID: creator)
    }

    @Test
    func onlyTheCreatorRemovesAndNeverThemselves() {
        let wg = group(members: ["du", "lena", "mats"], creator: "du")
        #expect(GroupPermissions.mayRemove("lena", from: wg, asking: "du"))
        #expect(!GroupPermissions.mayRemove("du", from: wg, asking: "du"))
        #expect(!GroupPermissions.mayRemove("mats", from: wg, asking: "lena"))
        #expect(!GroupPermissions.mayRemove("jemand", from: wg, asking: "du"))
    }

    @Test
    func onlyTheCreatorDeletesTheGroup() {
        let wg = group(members: ["du", "lena"], creator: "lena")
        #expect(GroupPermissions.mayDelete(wg, asking: "lena"))
        #expect(!GroupPermissions.mayDelete(wg, asking: "du"))
    }

    @Test
    func theLastMemberWhoCreatedItTakesTheGroupAlong() {
        #expect(GroupPermissions.leaving(group(members: ["du"], creator: "du"), asking: "du") == .deleteGroup)
        #expect(GroupPermissions.leaving(group(members: ["du", "lena"], creator: "du"), asking: "du") == .leave)
        // Last, but not the creator: the server would refuse the delete.
        #expect(GroupPermissions.leaving(group(members: ["du"], creator: "lena"), asking: "du") == .leave)
    }

    @Test
    func ownPostOnlyWhileItsRoundRuns() throws {
        let calendar = RoundDay.berlinCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12)))
        let earlier = now.addingTimeInterval(-3600)
        let yesterday = now.addingTimeInterval(-86_400)
        func post(by poster: String, at date: Date) -> Submission {
            Submission(id: 1, posterID: poster, track: "T", artist: "A",
                       coverColorHex: "#000000", comments: [], postedAt: date)
        }
        #expect(OwnContent.mayDelete(post(by: "du", at: earlier), asking: "du", now: now))
        #expect(!OwnContent.mayDelete(post(by: "du", at: yesterday), asking: "du", now: now))
        #expect(!OwnContent.mayDelete(post(by: "lena", at: earlier), asking: "du", now: now))
    }

    @Test
    func ownCommentsAndMessagesOnly() {
        let mine = Comment(id: 1, authorID: "du", authorName: "Du", text: "x", postedAt: .now)
        let theirs = Comment(id: 2, authorID: "lena", authorName: "Lena", text: "y", postedAt: .now)
        #expect(OwnContent.mayDelete(mine, asking: "du"))
        #expect(!OwnContent.mayDelete(theirs, asking: "du"))

        let sent = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "a",
                               isFromCurrentUser: true, authorID: "du")
        let received = ChatMessage(id: UUID(), authorTag: "LE", authorName: "Lena", text: "b",
                                   isFromCurrentUser: false, authorID: "lena")
        // The demo data carries no author id.
        let demo = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: "c",
                               isFromCurrentUser: true)
        #expect(OwnContent.mayDelete(sent, asking: "du"))
        #expect(!OwnContent.mayDelete(received, asking: "du"))
        #expect(OwnContent.mayDelete(demo, asking: "du"))
    }

    @Test
    func aConfirmationNamesTheMessageByItsFirstWords() {
        let long = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du",
                               text: String(repeating: "wort ", count: 20), isFromCurrentUser: true)
        let excerpt = ChatLayout.excerpt(of: long)
        #expect(excerpt.hasSuffix(" …"))
        #expect(excerpt.count <= 42)
        let song = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: " ",
                               isFromCurrentUser: true, mentionedSubmissionID: 3)
        #expect(ChatLayout.excerpt(of: song) == "Song-Erwähnung")
        #expect(CommentExcerpt.of("kurz") == "kurz")
    }
}

@Suite
@MainActor
struct LeaveAndDeleteStoreTests {
    private func store(_ repo: InMemoryRepository) -> AppStore {
        AppStore(groupRepo: repo, submissionRepo: repo, voteRepo: repo, chatRepo: repo,
                 battleRepo: repo, profileRepo: repo)
    }

    @Test
    func leavingDropsTheGroupAndChoosesAnother() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let before = store.groups.count
        let left = try #require(store.groups.first)
        store.selectGroup(left.id)

        #expect(await store.leaveGroup(left.id))

        #expect(store.groups.count == before - 1)
        #expect(!store.groups.contains { $0.id == left.id })
        #expect(store.currentGroupID != left.id)
    }

    @Test
    func theOnlyMemberLeavingDeletesTheGroup() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        #expect(await store.createGroup(name: "Allein", icon: "🎧"))
        let id = store.currentGroupID

        #expect(await store.leaveGroup(id))

        await #expect(throws: TodAppError.self) { try await repo.fetchGroup(id: id) }
    }

    @Test
    func theCreatorRemovesSomeoneElse() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let mine = try #require(store.groups.first { $0.creatorID == "du" })
        let other = try #require(mine.members.first { $0.id != "du" })

        #expect(await store.removeMember(other.id, from: mine.id))

        let after = try #require(store.groups.first { $0.id == mine.id })
        #expect(!after.members.contains { $0.id == other.id })
    }

    @Test
    func someoneElsesGroupIsNotDeleted() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let theirs = try #require(store.groups.first { $0.creatorID != "du" })

        let deleted = await store.deleteGroup(theirs.id)
        #expect(!deleted)
        #expect(store.groups.contains { $0.id == theirs.id })
        #expect(store.lastError == .notAllowed)
    }

    @Test
    func anOwnPostOfTodayCanBeTakenBack() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        #expect(await store.createGroup(name: "Neu", icon: "🎧"))
        let post = Submission(id: 9_001, posterID: "du", track: "Song", artist: "A",
                              coverColorHex: "#000000", comments: [])
        await store.submit(post)
        let posted = try #require(store.group(containing: 9_001)?.submissions.first)
        #expect(store.mayDelete(posted))

        #expect(await store.deleteSubmission(9_001))

        #expect(store.group(containing: 9_001) == nil)
    }

    @Test
    func anOwnCommentGoesAndAnotherOneStays() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        #expect(await store.createGroup(name: "Neu", icon: "🎧"))
        await store.submit(Submission(id: 9_002, posterID: "lena", track: "Song", artist: "A",
                                      coverColorHex: "#000000", comments: []))
        #expect(await store.addComment("erster", to: 9_002))
        #expect(await store.addComment("zweiter", to: 9_002))
        let comments = try #require(store.group(containing: 9_002)?.submissions.first?.comments)
        let first = try #require(comments.first)

        #expect(await store.deleteComment(first.id, on: 9_002))

        let left = try #require(store.group(containing: 9_002)?.submissions.first?.comments)
        #expect(left.map(\.text) == ["zweiter"])
    }

    @Test
    func anOwnMessageLeavesTheChat() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        await store.sendMessage("bis gleich")
        let sent = try #require(store.currentGroup?.chatMessages.last)

        #expect(await store.deleteMessage(sent.id))

        #expect(!(store.currentGroup?.chatMessages.contains { $0.id == sent.id } ?? true))
        let stored = try await repo.fetchMessages(groupID: store.currentGroupID)
        #expect(!stored.contains { $0.id == sent.id })
    }

    @Test
    func aMessageTheServerKeepsComesBack() async throws {
        let repo = InMemoryRepository()
        let store = store(repo)
        await store.loadGroups()
        let theirs = try #require(store.currentGroup?.chatMessages.first { !$0.isFromCurrentUser })

        let deleted = await store.deleteMessage(theirs.id)
        #expect(!deleted)

        #expect(store.currentGroup?.chatMessages.contains { $0.id == theirs.id } == true)
    }
}
