import Foundation

protocol GroupRepository: Sendable {
    func fetchGroups() async throws -> [Group]
    func fetchGroup(id: String) async throws -> Group

    /// Edits what a group looks like and who may invite. A nil `imageData`
    /// means "leave the picture alone", not "remove it" -- the settings screen
    /// edits name and picture independently, the same way the profile does.
    func updateGroup(
        id: String,
        name: String,
        imageData: Data?,
        invitePolicy: InvitePolicy
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
}
