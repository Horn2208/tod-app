import Foundation
import Testing
@testable import TodApp

@Suite
struct AppleSignInTests {
    /// The request carries the hash; Supabase compares it with the nonce, so
    /// the two must be SHA-256 in lowercase hex, exactly.
    @Test
    func theNonceIsHashedAsSHA256Hex() {
        #expect(AppleSignIn.hashed("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func everyAttemptGetsItsOwnNonce() {
        let one = AppleSignIn.makeNonce()
        let other = AppleSignIn.makeNonce()
        #expect(one.count == 32)
        #expect(one != other)
    }

    @Test
    func theGivenNameIsWhatTheGroupSees() {
        var name = PersonNameComponents()
        name.givenName = "Lena"
        name.familyName = "Schmidt"
        #expect(AppleSignIn.displayName(from: name) == "Lena")
    }

    @Test
    func withoutAGivenNameANicknameOrFamilyNameWillDo() {
        var nickname = PersonNameComponents()
        nickname.nickname = "Lenny"
        nickname.familyName = "Schmidt"
        var family = PersonNameComponents()
        family.givenName = "  "
        family.familyName = "Schmidt"
        #expect(AppleSignIn.displayName(from: nickname) == "Lenny")
        #expect(AppleSignIn.displayName(from: family) == "Schmidt")
    }

    /// Every sign-in after the first: Apple shares no name, and the profile
    /// keeps the one it has.
    @Test
    func noNameMeansNoRename() {
        #expect(AppleSignIn.displayName(from: nil) == nil)
        #expect(AppleSignIn.displayName(from: PersonNameComponents()) == nil)
    }

    /// The profile allows 40 characters.
    @Test
    func aLongNameIsCutToWhatTheProfileTakes() {
        var name = PersonNameComponents()
        name.givenName = String(repeating: "a", count: 60)
        #expect(AppleSignIn.displayName(from: name)?.count == 40)
    }
}
