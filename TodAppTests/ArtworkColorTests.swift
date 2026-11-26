import Foundation
import Testing
import UIKit
@testable import TodApp

@Suite
struct ArtworkColorTests {
    private typealias RGB = ArtworkColor.RGB

    private let grey = RGB(red: 0.5, green: 0.5, blue: 0.5)
    private let red = RGB(red: 0.8, green: 0.1, blue: 0.1)
    private let blue = RGB(red: 0.1, green: 0.2, blue: 0.8)
    private let mutedGreen = RGB(red: 0.3, green: 0.45, blue: 0.3)

    private func hue(_ colour: RGB?) -> Double? {
        colour.map { ArtworkColor.hsl($0).hue }
    }

    /// An average of equal values is equal only up to rounding.
    private func isClose(_ colour: RGB?, to expected: RGB) -> Bool {
        guard let colour else { return false }
        return abs(colour.red - expected.red) < 0.0001
            && abs(colour.green - expected.green) < 0.0001
            && abs(colour.blue - expected.blue) < 0.0001
    }

    @Test
    func greyBlackAndWhiteSayNothing() {
        let colourless = [grey, RGB(red: 0.02, green: 0.02, blue: 0.03), RGB(red: 1, green: 1, blue: 0.98)]
        #expect(ArtworkColor.dominant(in: colourless) == nil)
    }

    @Test
    func aColourWinsOverAMostlyGreyCover() {
        let cover = Array(repeating: grey, count: 90) + Array(repeating: blue, count: 10)
        #expect(isClose(ArtworkColor.dominant(in: cover), to: blue))
    }

    /// Counted alone, the green ground would win; weighted by colour, the red
    /// subject does.
    @Test
    func aVividSubjectBeatsALargerMutedGround() {
        let cover = Array(repeating: mutedGreen, count: 60) + Array(repeating: red, count: 40)
        #expect(isClose(ArtworkColor.dominant(in: cover), to: red))
    }

    @Test
    func shadesOfOneColourCountTogether() {
        let darkRed = RGB(red: 0.5, green: 0.05, blue: 0.08)
        // Blue alone outnumbers either shade of red, not both together.
        let cover = Array(repeating: red, count: 30) + Array(repeating: darkRed, count: 30)
            + Array(repeating: blue, count: 40)
        let winner = ArtworkColor.dominant(in: cover)
        #expect(hue(winner).map { $0 < 0.05 || $0 > 0.95 } == true)
    }

    /// A pale yellow cover still gives a glow white text can sit on.
    @Test
    func theGlowKeepsTheHueAtAFixedStrength() {
        let paleYellow = RGB(red: 0.98, green: 0.92, blue: 0.55)
        let glow = ArtworkColor.glow(for: paleYellow)
        let hsl = ArtworkColor.hsl(glow)
        #expect(abs(hsl.hue - ArtworkColor.hsl(paleYellow).hue) < 0.001)
        #expect(abs(hsl.lightness - ArtworkColor.glowLightness) < 0.001)
    }

    /// The whole way from image bytes: a PNG three quarters grey, one quarter
    /// blue, comes out blue.
    @MainActor
    @Test
    func aRealImageIsReadThroughItsPixels() throws {
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 30, y: 0, width: 10, height: 40))
        }
        let pixels = CoverPalette.pixels(in: png)
        #expect(pixels.count == 16 * 16)
        let winner = try #require(ArtworkColor.dominant(in: pixels))
        #expect(abs(ArtworkColor.hsl(winner).hue - ArtworkColor.hsl(blue).hue) < 0.03)
    }

    @Test
    func somethingThatIsNotAnImageHasNoPixels() {
        #expect(CoverPalette.pixels(in: Data("kein Bild".utf8)).isEmpty)
    }
}
