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
}
