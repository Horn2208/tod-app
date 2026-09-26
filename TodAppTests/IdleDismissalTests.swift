import Foundation
import Testing
@testable import TodApp

@Suite
struct IdleDismissalTests {
    private let touch = Date(timeIntervalSince1970: 1_000)

    @Test
    func itStaysWhileSomeoneWasJustThere() {
        #expect(!IdleDismissal.isDue(lastActivity: touch, now: touch.addingTimeInterval(5), isHeld: false))
    }

    @Test
    func itClosesOnceTheTimeIsUp() {
        #expect(IdleDismissal.isDue(
            lastActivity: touch, now: touch.addingTimeInterval(IdleDismissal.after), isHeld: false))
    }

    /// A comment half written, or the keyboard up, keeps it open however long.
    @Test
    func heldItNeverCloses() {
        #expect(!IdleDismissal.isDue(lastActivity: touch, now: touch.addingTimeInterval(600), isHeld: true))
    }

    /// The brief names 10 to 30 seconds.
    @Test
    func theWaitIsTenToThirtySeconds() {
        #expect((10.0...30.0).contains(IdleDismissal.after))
    }
}
