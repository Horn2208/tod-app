import Foundation

/// The signed-in person's own name and picture. Once per person, independent
/// of any group -- how someone shows up inside a group is `Member`.
protocol ProfileRepository: Sendable {
    func fetchProfile(userID: String) async throws -> UserProfile

    /// A nil `name` or `imageData` leaves that part alone, and so does a blank
    /// name: clearing the field to retype must not leave anyone nameless.
    func updateProfile(userID: String, name: String?, imageData: Data?) async throws
}
