import Foundation
import Testing
@testable import TodApp

@Suite
struct WaveformTests {
    /// The point of deriving it from the id: a song looks the same every time
    /// it is opened, and the shape never flickers between redraws.
    @Test
    func theSameTrackAlwaysGetsTheSameShape() {
        #expect(Waveform.bars(forTrack: "abc") == Waveform.bars(forTrack: "abc"))
    }

    @Test
    func differentTracksGetDifferentShapes() {
        #expect(Waveform.bars(forTrack: "abc") != Waveform.bars(forTrack: "xyz"))
    }

    /// Every bar feeds a SwiftUI frame height as a fraction of the row, so a
    /// value outside 0...1 is either an invisible bar or one that overflows.
    @Test
    func everyBarStaysWithinTheRow() {
        let bars = Waveform.bars(forTrack: "4cOdK2wGLETKBW3PvgPWqT", count: 60)

        #expect(bars.count == 60)
        #expect(bars.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    /// A bar of no height reads as a missing bar rather than a quiet moment.
    @Test
    func noBarCollapsesToNothing() {
        let bars = Waveform.bars(forTrack: "quiet", count: 200)

        #expect(bars.allSatisfy { $0 >= 0.14 })
    }

    /// The shape has to have some shape: a run of identical bars would be a
    /// block, which is what a broken generator produces.
    @Test
    func theShapeVaries() {
        let bars = Waveform.bars(forTrack: "abc", count: 40)

        #expect(Set(bars.map { Int($0 * 100) }).count > 10)
    }

    @Test
    func askingForNoBarsGivesNone() {
        #expect(Waveform.bars(forTrack: "abc", count: 0).isEmpty)
    }

    /// One bar has no width to spread an arc over; it must not divide by zero.
    @Test
    func aSingleBarIsFine() {
        let bars = Waveform.bars(forTrack: "abc", count: 1)

        #expect(bars.count == 1)
        #expect(bars[0].isFinite)
    }
}
