import Foundation
import Testing
@testable import TodApp

@Suite
struct PKCETests {
    /// RFC 7636 allows 43-128 characters from the unreserved set. Anything
    /// outside it is rejected by Spotify with a bare "invalid_request".
    @Test
    func aVerifierIsLongEnoughAndUsesOnlyUnreservedCharacters() {
        let verifier = PKCE.makeVerifier()
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        #expect(verifier.count >= 43)
        #expect(verifier.count <= 128)
        #expect(verifier.allSatisfy(allowed.contains))
    }

    @Test
    func twoVerifiersDiffer() {
        #expect(PKCE.makeVerifier() != PKCE.makeVerifier())
    }

    /// The one vector in RFC 7636 appendix B: this exact verifier must produce
    /// this exact challenge, or the exchange fails at Spotify with no useful
    /// message.
    @Test
    func theChallengeMatchesTheReferenceVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    /// The RFC 7636 reference vector contains + but no / in its base64 form,
    /// so it only exercises one of the two base64url substitutions. This second
    /// vector is chosen specifically to complement it: its SHA-256 contains two
    /// / and no +, verifying that the /→_ substitution is actually in place
    /// and not just dead code that would pass if deleted.
    @Test
    func theChallengeHandlesTheSlashSubstitution() {
        let verifier = "todapp-pkce-vector-0xxxxxxxxxxxxxxxxxxxxxxx"

        #expect(PKCE.challenge(for: verifier) == "NlpsspDVgSV2mcXS5lrdCYAagUAZfm1LF_x5XHKy_Hg")
    }

    /// Base64url never carries padding or the two characters that need
    /// escaping in a query string.
    @Test
    func theChallengeIsBase64URLWithoutPadding() {
        let challenge = PKCE.challenge(for: PKCE.makeVerifier())

        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }

    @Test
    func stateValuesDiffer() {
        #expect(PKCE.makeState() != PKCE.makeState())
    }
}
