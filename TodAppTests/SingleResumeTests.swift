import Foundation
import Testing
@testable import TodApp

/// Every test here would trap the whole test process rather than fail, if the
/// guard were removed -- that is exactly the failure mode being prevented.
@Suite
struct SingleResumeTests {
    @Test
    func theFirstValueWinsAndLaterOnesAreDropped() async throws {
        let value: String = try await withCheckedThrowingContinuation { continuation in
            let once = SingleResume<String>(continuation)
            once.resume(returning: "erste")
            once.resume(returning: "zweite")
            once.resume(throwing: TodAppError.authorizationFailed)
        }

        #expect(value == "erste")
    }

    @Test
    func aFailureAlsoClosesTheDoor() async {
        await #expect(throws: TodAppError.authorizationCancelled) {
            let _: String = try await withCheckedThrowingContinuation { continuation in
                let once = SingleResume<String>(continuation)
                once.resume(throwing: TodAppError.authorizationCancelled)
                once.resume(returning: "zu spät")
                once.resume(throwing: TodAppError.authorizationFailed)
            }
        }
    }

    /// The real shape of the crash: two callbacks arriving at once.
    @Test
    func concurrentResumesProduceExactlyOneOutcome() async throws {
        let value: Int = try await withCheckedThrowingContinuation { continuation in
            let once = SingleResume<Int>(continuation)
            DispatchQueue.concurrentPerform(iterations: 32) { index in
                once.resume(returning: index)
            }
        }

        #expect((0..<32).contains(value))
    }
}
