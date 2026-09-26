import MediaPlayer
import Testing
import UIKit
@testable import TodApp

/// The system asks for the lock screen's cover on a queue of its own. Made on
/// the main actor, the image closure trapped there (26. September).
@Suite
struct SystemArtworkTests {
    @Test
    func theCoverCanBeAskedForOffTheMainActor() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let artwork = await MiniPlayerBar.systemArtwork(image, size: image.size)
        let drawn = await withCheckedContinuation { done in
            DispatchQueue.global().async { done.resume(returning: artwork.image(at: CGSize(width: 8, height: 8))) }
        }
        #expect(drawn != nil)
    }
}
