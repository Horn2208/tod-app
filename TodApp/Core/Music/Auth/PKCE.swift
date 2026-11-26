import CryptoKit
import Foundation

/// The proof that ties an authorization code to the app that asked for it.
/// Without a client secret this is the only thing stopping someone who
/// intercepts the redirect from redeeming the code.
enum PKCE {
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Generates a 64-character verifier from unreserved characters.
    /// 64 characters is comfortably inside RFC 7636's 43-128 window and provides
    /// sufficient entropy for the PKCE proof. The fixed length prevents callers
    /// from accidentally creating verifiers outside the RFC's valid range.
    static func makeVerifier() -> String {
        String((0..<64).map { _ in unreserved.randomElement()! })
    }

    /// Generates a 32-character state value from unreserved characters.
    /// Fixed length provides sufficient entropy for CSRF protection while
    /// preventing accidental misconfiguration.
    static func makeState() -> String {
        String((0..<32).map { _ in unreserved.randomElement()! })
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
