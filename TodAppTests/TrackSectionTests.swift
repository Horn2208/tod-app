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
struct SectionTimelineTests {
    @Test
    func aMomentSitsAlongTheSong() {
        #expect(SectionTimeline.fraction(of: 60, in: 240) == 0.25)
        #expect(SectionTimeline.fraction(of: -5, in: 240) == 0)
        #expect(SectionTimeline.fraction(of: 300, in: 240) == 1)
    }

    /// No length, no line: nothing to divide by.
    @Test
    func aSongWithoutALengthHasEverythingAtItsStart() {
        #expect(SectionTimeline.fraction(of: 60, in: 0) == 0)
    }

    /// Four bars over 200 seconds: their middles lie at 25, 75, 125 and 175.
    @Test
    func aBarIsPlayedOnceThePlayheadReachesItsMiddle() {
        let played = (0..<4).map { SectionTimeline.isPlayed(bar: $0, of: 4, playhead: 80, total: 200) }
        #expect(played == [true, true, false, false])
        #expect(!SectionTimeline.isPlayed(bar: 0, of: 4, playhead: 24, total: 200))
        #expect(SectionTimeline.isPlayed(bar: 0, of: 4, playhead: 25, total: 200))
    }
}
