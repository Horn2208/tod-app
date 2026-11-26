import Testing
@testable import TodApp

struct SoundCloudTermsTests {
    @Test func searchIsOffOnlyInTheAppStore() {
        #expect(SoundCloudSearchPolicy.isAllowed(in: .debug))
        #expect(SoundCloudSearchPolicy.isAllowed(in: .testFlight))
        #expect(!SoundCloudSearchPolicy.isAllowed(in: .appStore))
    }

    @Test func creditNamesUploaderAndSoundCloud() {
        #expect(SoundCloudAttribution.text(uploader: "Forss") == "Von Forss · auf SoundCloud")
    }

    @Test func creditWithoutUploaderStillNamesSoundCloud() {
        #expect(SoundCloudAttribution.text(uploader: "  ") == "Auf SoundCloud")
    }

    @Test func uploaderCreditBesideTheWordmark() {
        #expect(SoundCloudAttribution.uploaderCredit("Forss") == "· von Forss")
        #expect(SoundCloudAttribution.uploaderCredit(" ") == nil)
    }
}
