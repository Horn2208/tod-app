import Foundation
import Testing
@testable import TodApp

/// A code is typed by hand, read off a screen or pasted from a message; the
/// rules make all three land on the same code.
@Suite
struct InviteCodeTests {
    @Test
    func spacesDashesAndCapitalsAreIgnored() {
        #expect(InviteCode.normalized(" ABCD-ef01 2345-6789\n") == "abcdef0123456789")
    }

    @Test
    func aPlausibleCodeIsSixteenHexDigits() {
        #expect(InviteCode.isPlausible("abcd-ef01-2345-6789"))
        #expect(InviteCode.isPlausible("abcdef012345678") == false)
        #expect(InviteCode.isPlausible("abcdef01234567890") == false)
        // A typo is not quietly dropped into a valid-looking code.
        #expect(InviteCode.isPlausible("abcdef012345678g") == false)
        #expect(InviteCode.isPlausible("") == false)
    }

    /// Sixteen letters in a row are hard to read out; blocks of four are not.
    @Test
    func aCodeIsShownInBlocksOfFour() {
        #expect(InviteCode.display("abcdef0123456789") == "abcd-ef01-2345-6789")
    }

    /// The message says where the code goes, since there is no link to tap.
    @Test
    func theSharedMessageNamesTheGroupTheCodeAndWhereToEnterIt() {
        let text = InviteCode.message(groupName: "WG Chaos", code: "abcdef0123456789")

        #expect(text == """
            Komm in meine Gruppe „WG Chaos“ bei TodApp. \
            Unter Gruppen → + → Mit Code beitreten eingeben: abcd-ef01-2345-6789
            """)
    }
}

@Suite
struct NewGroupDraftTests {
    @Test
    func aNameIsTrimmed() {
        #expect(NewGroupDraft.name("  WG Chaos \n") == "WG Chaos")
    }

    @Test
    func aBlankNameIsNoName() {
        #expect(NewGroupDraft.name("   ") == nil)
    }

    /// The database counts characters as Unicode scalars; a name the server
    /// would refuse is refused here first. Nine family emoji look like nine
    /// characters and are 45 scalars.
    @Test
    func aNameLongerThanTheDatabaseAllowsIsNoName() {
        #expect(NewGroupDraft.name(String(repeating: "a", count: 40)) != nil)
        #expect(NewGroupDraft.name(String(repeating: "a", count: 41)) == nil)
        #expect(NewGroupDraft.name(String(repeating: "👨‍👩‍👧", count: 9)) == nil)
    }

    @Test
    func theIconIsTheFirstCharacter() {
        #expect(NewGroupDraft.icon(" 🏠🎸") == "🏠")
        #expect(NewGroupDraft.icon("👨‍👩‍👧") == "👨‍👩‍👧")
    }

    @Test
    func noIconMeansTheNote() {
        #expect(NewGroupDraft.icon("  ") == "🎵")
    }
}

@Suite
struct InMemoryMembershipTests {
    @Test
    func aNewGroupHasItsMakerAsCreatorAndOnlyMember() async throws {
        let repo = InMemoryRepository()

        let id = try await repo.createGroup(name: "Band", icon: "🎸", asking: "du")

        let group = try await repo.fetchGroup(id: id)
        #expect(group.name == "Band")
        #expect(group.icon == "🎸")
        #expect(group.creatorID == "du")
        #expect(group.invitePolicy == .everyone)
        #expect(group.members.map(\.id) == ["du"])
        #expect(group.members.first?.isCurrentUser == true)
        #expect(group.submissions.isEmpty)
    }

    @Test
    func aMemberOfAnOpenGroupGetsACode() async throws {
        let repo = InMemoryRepository()

        let invite = try await repo.createInvite(groupID: "wg", asking: "du")

        #expect(invite.groupID == "wg")
        #expect(InviteCode.isPlausible(invite.code))
        #expect(invite.expiresAt > Date().addingTimeInterval(6 * 24 * 3600))
    }

    /// `lnc` is Lena's, and she kept inviting to herself.
    @Test
    func aClosedGroupGivesNoCodeToSomeoneElse() async throws {
        let repo = InMemoryRepository()

        await #expect(throws: TodAppError.notAllowed) {
            try await repo.createInvite(groupID: "lnc", asking: "du")
        }
    }

    @Test
    func theCreatorOfAClosedGroupStillGetsACode() async throws {
        let repo = InMemoryRepository()

        let invite = try await repo.createInvite(groupID: "lnc", asking: "lena")

        #expect(invite.groupID == "lnc")
    }

    /// The code as someone would type it, in capitals and with dashes.
    @Test
    func aCodeLeadsIntoItsGroup() async throws {
        let repo = InMemoryRepository()
        let invite = try await repo.createInvite(groupID: "wg", asking: "du")

        let joined = try await repo.joinGroup(
            code: InviteCode.display(invite.code).uppercased(), asking: "kim")

        #expect(joined == "wg")
        #expect(try await repo.fetchGroup(id: "wg").members.contains { $0.id == "kim" })
    }

    /// Joining twice leaves one membership.
    @Test
    func joiningAgainChangesNothing() async throws {
        let repo = InMemoryRepository()
        let invite = try await repo.createInvite(groupID: "wg", asking: "du")

        _ = try await repo.joinGroup(code: invite.code, asking: "du")

        let members = try await repo.fetchGroup(id: "wg").members
        #expect(members.filter { $0.id == "du" }.count == 1)
    }

    @Test
    func anUnknownCodeIsInvalid() async throws {
        let repo = InMemoryRepository()

        await #expect(throws: TodAppError.inviteInvalid) {
            try await repo.joinGroup(code: "0000000000000000", asking: "du")
        }
    }
}

@Suite
struct InMemoryProfileTests {
    @Test
    func theLocalProfileIsThere() async throws {
        let repo = InMemoryRepository()

        let profile = try await repo.fetchProfile(userID: "du")

        #expect(profile.id == "du")
        #expect(profile.name == "Du")
    }

    @Test
    func aRenameIsKept() async throws {
        let repo = InMemoryRepository()

        try await repo.updateProfile(userID: "du", name: "  Lennet ", imageData: nil)

        #expect(try await repo.fetchProfile(userID: "du").name == "Lennet")
    }

    /// Clearing the field to retype must not leave anyone nameless.
    @Test
    func aBlankNameChangesNothing() async throws {
        let repo = InMemoryRepository()

        try await repo.updateProfile(userID: "du", name: "  ", imageData: nil)

        #expect(try await repo.fetchProfile(userID: "du").name == "Du")
    }

    @Test
    func aPictureIsKeptAndANameAloneLeavesIt() async throws {
        let repo = InMemoryRepository()
        let picture = Data([7])

        try await repo.updateProfile(userID: "du", name: nil, imageData: picture)
        try await repo.updateProfile(userID: "du", name: "Lennet", imageData: nil)

        let profile = try await repo.fetchProfile(userID: "du")
        #expect(profile.imageData == picture)
        #expect(profile.name == "Lennet")
    }

    @Test
    func someoneElsesProfileIsNotFound() async throws {
        let repo = InMemoryRepository()

        await #expect(throws: TodAppError.notFound) {
            try await repo.fetchProfile(userID: "lena")
        }
    }
}
