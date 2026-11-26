import Foundation
import Testing
@testable import TodApp

private struct SampleError: Error {
    let code: Int
}

@Suite
struct TodAppErrorTests {
    @Test
    func networkWrappingDifferentErrorsIsNeverEqual() {
        let a = TodAppError.network(underlying: SampleError(code: 404))
        let b = TodAppError.network(underlying: SampleError(code: 500))

        #expect(a != b)
    }

    @Test
    func networkWrappingTheSameErrorIsStillNeverEqual() {
        // Deliberate: NSError-bridging would make this compare equal even
        // though we cannot actually verify the payloads match, so `.network`
        // never claims equality -- not even to itself. Do not "fix" this.
        let error = SampleError(code: 404)
        let a = TodAppError.network(underlying: error)
        let b = TodAppError.network(underlying: error)

        #expect(a != b)
    }

}
