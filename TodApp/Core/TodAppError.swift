import Foundation

enum TodAppError: Error {
    case notFound
    case alreadyVoted
    case network(underlying: Error)
}
