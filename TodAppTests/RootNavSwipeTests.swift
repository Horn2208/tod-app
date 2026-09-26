import Testing
@testable import TodApp

/// The glass bar at the bottom answers a finger sliding along it, as the
/// system tab bar did.
@Suite
struct RootNavSwipeTests {
    /// Together, the bar is two halves: a finger over the right one means
    /// Gruppen, over the left one Home.
    @Test
    func theHalfUnderTheFingerIsThePage() {
        #expect(RootNavSwipe.page(atX: 20, barWidth: 180) == .home)
        #expect(RootNavSwipe.page(atX: 150, barWidth: 180) == .gruppen)
        // Past either end the nearest page stays.
        #expect(RootNavSwipe.page(atX: -30, barWidth: 180) == .home)
        #expect(RootNavSwipe.page(atX: 400, barWidth: 180) == .gruppen)
    }

    /// Apart, with the player between, a swipe moves one page along; a short
    /// nudge moves nothing.
    @Test
    func aSwipeMovesOnePage() {
        #expect(RootNavSwipe.page(afterSwipe: -80, from: .home) == .gruppen)
        #expect(RootNavSwipe.page(afterSwipe: 80, from: .gruppen) == .home)
        #expect(RootNavSwipe.page(afterSwipe: -80, from: .gruppen) == .gruppen)
        #expect(RootNavSwipe.page(afterSwipe: 20, from: .gruppen) == .gruppen)
    }

    /// Across the page: the same direction as on the bar.
    @Test
    func aSwipeAcrossThePageMovesLikeOnTheBar() {
        #expect(RootNavSwipe.page(
            afterContentSwipe: -120, dy: 10, from: .home, isAtRoot: true, beganInSidewaysRow: false) == .gruppen)
        #expect(RootNavSwipe.page(
            afterContentSwipe: 120, dy: -10, from: .gruppen, isAtRoot: true, beganInSidewaysRow: false) == .home)
    }

    /// Scrolling down with a finger that drifts sideways is still scrolling.
    @Test
    func aMostlyUpOrDownSwipeKeepsThePage() {
        #expect(RootNavSwipe.page(
            afterContentSwipe: -90, dy: 200, from: .home, isAtRoot: true, beganInSidewaysRow: false) == .home)
    }

    /// Across the page it takes further than a nudge on the bar.
    @Test
    func aShortSwipeAcrossThePageKeepsIt() {
        #expect(RootNavSwipe.page(
            afterContentSwipe: -45, dy: 0, from: .home, isAtRoot: true, beganInSidewaysRow: false) == .home)
    }

    /// A pushed screen -- the rating feed turns its pages sideways -- keeps
    /// its own swipes.
    @Test
    func aPushedScreenKeepsItsSwipes() {
        #expect(RootNavSwipe.page(
            afterContentSwipe: -120, dy: 0, from: .home, isAtRoot: false, beganInSidewaysRow: false) == .home)
    }

    /// The group switcher and the story row scroll sideways themselves.
    @Test
    func aSwipeInASidewaysRowMovesTheRow() {
        #expect(RootNavSwipe.page(
            afterContentSwipe: -120, dy: 0, from: .home, isAtRoot: true, beganInSidewaysRow: true) == .home)
    }
}
