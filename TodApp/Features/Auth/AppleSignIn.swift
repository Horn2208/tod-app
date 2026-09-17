import CryptoKit
import Foundation

/// The pieces of Sign in with Apple that are not a system sheet.
enum AppleSignIn {
    /// A fresh random string for one sign-in attempt. Apple gets its hash and
    /// writes that into the identity token; Supabase gets the string itself
    /// and checks the two match, so a token caught in transit is useless for
    /// another sign-in.
    static func makeNonce(length: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// What goes into the request: SHA-256 of the nonce, as lowercase hex.
    static func hashed(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The name a group sees, from what Apple shares on a first sign-in: the
    /// given name, as friends call each other, else a nickname. Nil when Apple
    /// shares nothing -- every sign-in after the first.
    static func displayName(from name: PersonNameComponents?) -> String? {
        let candidates = [name?.givenName, name?.nickname, name?.familyName]
        let first = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return first.map { String($0.prefix(40)) }
    }
}
