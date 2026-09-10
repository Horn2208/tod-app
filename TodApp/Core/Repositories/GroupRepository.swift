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

    /// Brings someone new in. Whether the asker is allowed to is
    /// `GroupPermissions.mayInvite`'s answer, checked here as well as in the
    /// view -- a permission that only a button enforces is a suggestion.
    func addMember(named name: String, to groupID: String, asking userID: String) async throws
}
