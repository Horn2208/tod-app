import Foundation
import Testing
@testable import TodApp

@Suite
struct TrackSectionTests {
    private let total: Double = 222  // 3:42, the prototype's track

    @Test
    func theDefaultSectionIsThirtySecondsInsideTheTrack() {
        let section = TrackSection.initial(in: total)

        #expect(section.duration == 30)
        #expect(section.start >= 0)
        #expect(section.end <= total)
    }

    /// A jingle shorter than the minimum still has to produce something the
    /// handles can sit on, rather than an inverted range.
    @Test
    func aTrackShorterThanTheMinimumBecomesTheWholeTrack() {
        let section = TrackSection.initial(in: 3)

        #expect(section.start == 0)
        #expect(section.end == 3)
    }

    @Test
    func draggingTheStartCannotPassTheEnd() {
        var section = TrackSection(start: 80, end: 110)

        section.moveStart(to: 200, in: total)

        #expect(section.start == 105)  // end - minimumDuration
        #expect(section.end == 110)
    }

    @Test
    func draggingTheEndCannotPassTheStart() {
        var section = TrackSection(start: 80, end: 110)

        section.moveEnd(to: 10, in: total)

        #expect(section.end == 85)  // start + minimumDuration
        #expect(section.start == 80)
    }

    @Test
    func handlesStayInsideTheTrack() {
        var section = TrackSection(start: 80, end: 110)

        section.moveStart(to: -40, in: total)
        #expect(section.start == 0)

        section.moveEnd(to: total + 40, in: total)
        #expect(section.end == total)
    }

    /// Dragging the window as a whole keeps its length -- it slides, it does not
    /// stretch against the edge.
    @Test
    func movingTheWholeWindowKeepsItsLength() {
        var section = TrackSection(start: 80, end: 110)

        section.move(toStart: 150, in: total)

        #expect(section.start == 150)
        #expect(section.duration == 30)
    }

    @Test
    func movingTheWindowPastTheEndParksItAgainstTheEdge() {
        var section = TrackSection(start: 80, end: 110)

        section.move(toStart: 1000, in: total)

        #expect(section.end == total)
        #expect(section.duration == 30)
    }

    @Test
    func movingTheWindowBeforeZeroParksItAtTheStart() {
        var section = TrackSection(start: 80, end: 110)

        section.move(toStart: -50, in: total)

        #expect(section.start == 0)
        #expect(section.duration == 30)
    }

    @Test
    func aSectionSurvivesEncodingSoASubmissionCanCarryIt() throws {
        let section = TrackSection(start: 82, end: 112)

        let decoded = try JSONDecoder().decode(
            TrackSection.self, from: JSONEncoder().encode(section)
        )

        #expect(decoded == section)
    }
}

@Suite
struct WaveformShapeTests {
    /// The prototype rerolls its bars on every build, so the same song looks
    /// different twice. Deriving them from the track id keeps a song's shape.
    @Test
    func theSameTrackAlwaysGetsTheSameShape() {
        let first = WaveformShape.bars(count: 48, seed: "4cOdK2wGLETKBW3PvgPWqT")
        let second = WaveformShape.bars(count: 48, seed: "4cOdK2wGLETKBW3PvgPWqT")

        #expect(first == second)
    }

    @Test
    func differentTracksGetDifferentShapes() {
        let one = WaveformShape.bars(count: 48, seed: "4cOdK2wGLETKBW3PvgPWqT")
        let other = WaveformShape.bars(count: 48, seed: "7ouMYWpwJ422jRcDASZB7P")

        #expect(one != other)
    }

    @Test
    func everyBarIsVisibleAndFitsTheTrack() {
        let bars = WaveformShape.bars(count: 48, seed: "abc")

        #expect(bars.count == 48)
        #expect(bars.allSatisfy { $0 >= 0.14 && $0 <= 1 })
    }

    @Test
    func askingForNoBarsGivesNone() {
        #expect(WaveformShape.bars(count: 0, seed: "abc").isEmpty)
    }
}
