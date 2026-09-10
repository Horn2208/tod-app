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
    /// Whether Tod Premium is on. A plain flag on purpose: nothing here talks
    /// to StoreKit yet, and the point of putting it in the model now is that
    /// the locks in the UI read a purchase state rather than a hard-coded
    /// `false` -- later only this one value has to come from a real receipt.
    var isPremium: Bool = false
}
