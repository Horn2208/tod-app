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

/// Pictures (`docs/prompt.md`, item 22): a picked photo is shrunk before it
/// is kept, and a profile or group picture is decoded once.
@Suite
@MainActor
struct PictureTests {
    private func photo(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.systemPink.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
        return image.jpegData(compressionQuality: 0.9)!
    }

    @Test
    func aPickedPhotoIsShrunkBeforeItIsKept() async throws {
        let big = photo(width: 3000, height: 2000)

        let small = try #require(await ImageDownscale.shrunk(big))

        let image = try #require(UIImage(data: small))
        #expect(max(image.size.width, image.size.height) <= 1024)
        #expect(small.count < big.count)
    }

    @Test
    func somethingThatIsNoPictureIsRefused() async {
        #expect(await ImageDownscale.shrunk(Data([0x01, 0x02])) == nil)
    }

    @Test
    func aPictureIsDecodedOnce() throws {
        let data = photo(width: 40, height: 40)

        let first = try #require(DecodedPictures.image(from: data))
        let second = try #require(DecodedPictures.image(from: data))

        #expect(first === second)
        #expect(DecodedPictures.image(from: Data([0x01])) == nil)
    }
}
