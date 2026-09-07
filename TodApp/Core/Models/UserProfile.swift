import Foundation

/// The person using the app. Until now they existed only as the string "du"
/// and a flag on `Member`; the profile screen needs somewhere to put a name
/// and a picture.
struct UserProfile: Codable, Equatable {
    let id: String
    var name: String
    /// Raw image bytes rather than a URL: everything here is in memory, and a
    /// picked photo has no address to point at.
    var imageData: Data?
}
