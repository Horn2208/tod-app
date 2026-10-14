import Testing
@testable import TodApp

struct NamePromptTests {
    @Test
    func onlyTheDefaultOrABlankNameIsAsked() {
        #expect(UserProfile.needsName("Neu"))
        #expect(UserProfile.needsName(" Neu "))
        #expect(UserProfile.needsName("   "))
        #expect(!UserProfile.needsName("Lena"))
    }
}
