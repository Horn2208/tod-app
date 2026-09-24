import Testing
@testable import TodApp

@Suite
struct PrivacyPolicyTests {
    /// Name, address and contact are the owner's to fill in. Until then this
    /// is a known issue; once filled in, it passes and Swift Testing says so.
    @Test
    func theResponsiblePersonIsFilledIn() {
        withKnownIssue("Verantwortlicher und Kontakt fehlen noch") {
            #expect(PrivacyPolicy.isComplete)
        }
    }

    /// What the policy promises has to be what the app does: deletion lives
    /// in the profile, and there is no tracking.
    @Test
    func thePolicySaysWhatTheAppDoes() {
        let text = PrivacyPolicy.sections.map(\.body).joined(separator: " ")
        #expect(text.contains("Im Profil kannst du es jederzeit löschen"))
        #expect(text.contains("kein Tracking"))
        #expect(text.contains("Supabase"))
    }
}
