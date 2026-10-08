import Foundation

protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [Group]
    func fetchGroup(id: String) async throws -> Group

    /// Edits what a group looks like and who may invite. Nil leaves that part
    /// alone -- nil `imageData` does not remove the picture -- and so does a
    /// blank name. A save carries only what it changes: one that carried the
    /// whole group could put back a setting another save had just changed.
    func updateGroup(
        id: String,
        name: String?,
        imageData: Data?,
        invitePolicy: InvitePolicy?
    ) async throws

    /// Starts a group with the asker as its creator and first member, and
    /// returns its id.
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String

    /// A code someone else can join with. Whether the asker may hand one out
    /// is `GroupPermissions.mayInvite`'s answer, checked here as well as in
    /// the view -- a permission that only a button enforces is a suggestion.
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite

    /// Joins the group a code belongs to and returns its id. Joining a group
    /// one is already in changes nothing.
    func joinGroup(code: String, asking userID: String) async throws -> String

    /// Takes the asker out of the group. Whether the group goes with them is
    /// the caller's question (`GroupPermissions.leaving`).
    func leaveGroup(id: String, asking userID: String) async throws

    /// Takes someone else out -- only the creator may (`GroupPermissions.mayRemove`).
    func removeMember(_ memberID: String, from groupID: String, asking userID: String) async throws

    /// Deletes the group for everyone, with its posts, votes and chat.
    func deleteGroup(id: String, asking userID: String) async throws
}

extension GroupRepository {
    // Refused unless a repository says otherwise, so the test doubles that
    // never leave a group need not spell it out.
    func leaveGroup(id: String, asking userID: String) async throws { throw TodAppError.notAllowed }
    func removeMember(_ memberID: String, from groupID: String, asking userID: String) async throws {
        throw TodAppError.notAllowed
    }
    func deleteGroup(id: String, asking userID: String) async throws { throw TodAppError.notAllowed }
}
