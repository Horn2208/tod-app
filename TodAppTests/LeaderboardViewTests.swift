import Foundation
import Testing
@testable import TodApp

/// The bar width is the one piece of arithmetic in the leaderboard, and it
/// divides by a number the board itself supplies.
@Suite
struct LeaderboardBarTests {
    @Test
    func theLeaderFillsTheRowAndTheRestScaleAgainstIt() {
        #expect(LeaderboardView.barFraction(points: 210, max: 210) == 1)
        #expect(LeaderboardView.barFraction(points: 105, max: 210) == 0.5)
        #expect(LeaderboardView.barFraction(points: 0, max: 210) == 0)
    }

    /// A board on which nobody has scored yet divides zero by zero. The NaN
    /// that produces reaches SwiftUI as a frame width, which is not a dimension
    /// it accepts.
    @Test
    func aBoardWhereNobodyHasScoredDrawsNoBarInsteadOfNaN() {
        let fraction = LeaderboardView.barFraction(points: 0, max: 0)

        #expect(fraction.isFinite)
        #expect(fraction == 0)
    }

    /// Points can go negative once a round of Aussetzer counts, and a negative
    /// width is refused just as loudly as a NaN one.
    @Test
    func aNegativeScoreDrawsNoBarRatherThanANegativeWidth() {
        #expect(LeaderboardView.barFraction(points: -40, max: 210) == 0)
        #expect(LeaderboardView.barFraction(points: -40, max: -10) == 0)
    }

    /// Nothing may draw wider than the row it sits in.
    @Test
    func noBarOverflowsItsRow() {
        #expect(LeaderboardView.barFraction(points: 300, max: 210) == 1)
    }
}
