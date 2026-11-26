import MusicKit
import Testing
@testable import TodApp

@Suite
struct AppleMusicAccessTests {
    @Test
    func nobodyAskedYetIsNotAsked() {
        #expect(AppleMusicAccess.standing(authorization: .notDetermined, canPlayCatalogContent: nil) == .notAsked)
    }

    /// Screen Time's block reads the same as a "no": only Settings undoes it.
    @Test
    func declinedAndRestrictedAreBothDenied() {
        #expect(AppleMusicAccess.standing(authorization: .denied, canPlayCatalogContent: nil) == .denied)
        #expect(AppleMusicAccess.standing(authorization: .restricted, canPlayCatalogContent: nil) == .denied)
    }

    @Test
    func aSubscriptionThatPlaysCatalogSongsGivesWholeSongs() {
        #expect(AppleMusicAccess.standing(authorization: .authorized, canPlayCatalogContent: true) == .wholeSongs)
    }

    @Test
    func allowedWithoutASubscriptionIsPreviewsOnly() {
        #expect(AppleMusicAccess.standing(authorization: .authorized, canPlayCatalogContent: false) == .previewsOnly)
    }

    /// Before the subscription has been read, the player must not reach for
    /// songs it may not be able to play.
    @Test
    func anUnreadSubscriptionCountsAsNone() {
        #expect(AppleMusicAccess.standing(authorization: .authorized, canPlayCatalogContent: nil) == .previewsOnly)
    }
}
