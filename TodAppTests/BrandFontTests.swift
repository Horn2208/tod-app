import Testing
import SwiftUI
import UIKit
@testable import TodApp

/// The brand's fonts are in the app: a name that does not resolve falls back
/// to the system font silently, which is how the app ran without them.
@Suite
struct BrandFontTests {
    @Test(arguments: BrandFont.allNames)
    func everyFaceTheAppAsksForIsBundled(name: String) {
        #expect(UIFont(name: name, size: 14) != nil, "\(name) is not registered")
    }

    @Test
    func weightsPickTheNearestFace() {
        #expect(BrandFont.body(.regular) == "Manrope-Regular")
        #expect(BrandFont.body(.semibold) == "Manrope-SemiBold")
        #expect(BrandFont.mono(.medium) == "JetBrainsMono-Medium")
        #expect(BrandFont.mono(.heavy) == "JetBrainsMono-Bold")
        #expect(BrandFont.body(.light) == "Manrope-Regular")
    }
}
