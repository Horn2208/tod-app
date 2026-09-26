import StoreKit

/// Where this copy of the app came from.
enum AppDistribution: Equatable, Sendable {
    case debug, testFlight, appStore

    /// Debug builds from Xcode; otherwise what the App Store says about this
    /// install. TestFlight installs are in its sandbox. When the App Store
    /// cannot answer, the strictest answer: the App Store.
    static func current() async -> AppDistribution {
        #if DEBUG
        return .debug
        #else
        guard let transaction = try? await AppTransaction.shared else { return .appStore }
        return transaction.unsafePayloadValue.environment == .sandbox ? .testFlight : .appStore
        #endif
    }
}

/// Whether "Song posten" searches SoundCloud.
///
/// The search reads SoundCloud's public search page (`SoundCloudSearchClient`),
/// and SoundCloud's API Terms (section 10) forbid scraping. Tolerable while a
/// handful of testers use the app; not in the App Store, where only pasted
/// SoundCloud links (oEmbed, an official interface) remain. See the redesign
/// brief, "SoundCloud: was erlaubt ist".
enum SoundCloudSearchPolicy {
    static func isAllowed(in distribution: AppDistribution) -> Bool {
        distribution != .appStore
    }
}

/// The credit SoundCloud's API Terms (section 8) ask for wherever one of its
/// sounds plays: the uploader, and SoundCloud as the source.
enum SoundCloudAttribution {
    static func text(uploader: String) -> String {
        let name = uploader.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Auf SoundCloud" : "Von \(name) · auf SoundCloud"
    }
}
