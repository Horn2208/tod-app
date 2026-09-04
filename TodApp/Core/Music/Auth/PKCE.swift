import CryptoKit
import Foundation

/// The proof that ties an authorization code to the app that asked for it.
/// Without a client secret this is the only thing stopping someone who
/// intercepts the redirect from redeeming the code.
enum PKCE {
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// 64 characters: comfortably inside RFC 7636's 43-128 window.
    static func makeVerifier(length: Int = 64) -> String {
        String((0..<length).map { _ in unreserved.randomElement()! })
    }

    static func makeState(length: Int = 32) -> String {
        String((0..<length).map { _ in unreserved.randomElement()! })
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Base64url per RFC 4648 §5: no padding, and the two substitutions that
    /// keep the value safe inside a query string.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
