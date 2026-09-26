import Foundation
import Testing
import UIKit
@testable import TodApp

/// What lets Home carry a cover and its glow across a group change: what was
/// read once is there again at once.
@Suite
@MainActor
struct CoverCacheTests {
    /// A blue square as a file, so no test reaches the network.
    private func blueCover() throws -> URL {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    @Test
    func aCoverNotLoadedYetIsNotCached() throws {
        #expect(CoverImages.shared.cached(try blueCover()) == nil)
    }

    /// Back to a group: its cover shows without loading again.
    @Test
    func aLoadedCoverIsThereAtOnce() async throws {
        let url = try blueCover()

        let loaded = await CoverImages.shared.image(for: url)

        #expect(loaded != nil)
        #expect(CoverImages.shared.cached(url) != nil)
    }

    @Test
    func somethingThatIsNotAPictureLoadsAsNothing() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-cover-\(UUID().uuidString).png")
        try Data("kein Bild".utf8).write(to: url)

        #expect(await CoverImages.shared.image(for: url) == nil)
        #expect(CoverImages.shared.cached(url) == nil)
    }

    /// The glow starts in the cover's colour, not the derived one, once the
    /// cover has been read.
    @Test
    func aReadGlowIsThereWithoutWaiting() async throws {
        let url = try blueCover()
        #expect(CoverPalette.shared.cachedGlow(for: url) == nil)

        let glow = await CoverPalette.shared.glow(for: url)

        #expect(glow != nil)
        #expect(CoverPalette.shared.cachedGlow(for: url) == glow)
    }
}
