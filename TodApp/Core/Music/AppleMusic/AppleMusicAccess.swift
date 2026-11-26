import Foundation
import MusicKit
import Observation

/// What Apple Music on this device can do for the app: whether the listener
/// has allowed it, and whether their subscription plays whole songs.
///
/// App-wide and observable, because two places care -- the profile, which
/// offers to connect, and the player, which picks whole songs over the preview
/// once they are there.
@MainActor
@Observable
final class AppleMusicAccess {
    enum Standing: Equatable, Sendable {
        /// Nobody has been asked yet.
        case notAsked
        /// Declined, or blocked by Screen Time. Only the Settings app can undo it.
        case denied
        /// Allowed, but no subscription that plays catalog songs.
        case previewsOnly
        /// Allowed, with a subscription: whole songs, from the picked section.
        case wholeSongs
    }

    private(set) var standing: Standing

    var playsWholeSongs: Bool { standing == .wholeSongs }

    init() {
        standing = Self.standing(authorization: MusicAuthorization.currentStatus, canPlayCatalogContent: nil)
    }

    /// Shows the system prompt -- iOS does so only the first time -- then
    /// looks at the subscription.
    func connect() async {
        _ = await MusicAuthorization.request()
        await refresh()
    }

    func refresh() async {
        let status = MusicAuthorization.currentStatus
        // The subscription is only readable once access is granted.
        let canPlay = status == .authorized
            ? (try? await MusicSubscription.current)?.canPlayCatalogContent
            : nil
        standing = Self.standing(authorization: status, canPlayCatalogContent: canPlay)
    }

    /// Follows the subscription for as long as the app runs: someone who
    /// subscribes in the Music app should not have to restart this one.
    func followSubscription() async {
        for await subscription in MusicSubscription.subscriptionUpdates {
            standing = Self.standing(
                authorization: MusicAuthorization.currentStatus,
                canPlayCatalogContent: subscription.canPlayCatalogContent)
        }
    }

    /// Pure, so it is tested without MusicKit answering anything.
    nonisolated static func standing(
        authorization: MusicAuthorization.Status,
        canPlayCatalogContent: Bool?
    ) -> Standing {
        switch authorization {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        // Unknown counts as no: a subscription that has not been read yet
        // must not send the player after songs it cannot play.
        case .authorized: return canPlayCatalogContent == true ? .wholeSongs : .previewsOnly
        @unknown default: return .denied
        }
    }
}
