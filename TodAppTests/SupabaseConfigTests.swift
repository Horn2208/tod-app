import Foundation
import Testing
@testable import TodApp

/// A build knows its Supabase project only when both values arrived; anything
/// else means no backend, not a half-configured one.
@Suite
struct SupabaseConfigTests {
    private let address = "https://abcdefghijklmnop.supabase.co"
    private let key = "public-client-key"

    @Test
    func bothValuesMakeAProject() throws {
        let config = try #require(SupabaseConfig.from(info: [
            "SupabaseURL": address, "SupabaseAnonKey": key,
        ]))
        #expect(config.url.host() == "abcdefghijklmnop.supabase.co")
        #expect(config.anonKey == key)
    }

    /// Built without Config/Secrets.xcconfig: the settings are empty.
    @Test
    func emptyValuesMeanNoBackend() {
        #expect(SupabaseConfig.from(info: ["SupabaseURL": "", "SupabaseAnonKey": ""]) == nil)
        #expect(SupabaseConfig.from(info: [:]) == nil)
    }

    /// A setting nobody defined can reach the plist as its own name.
    @Test
    func anUnexpandedSettingIsNotAnAddress() {
        let info = ["SupabaseURL": "$(SUPABASE_URL)", "SupabaseAnonKey": "$(SUPABASE_ANON_KEY)"]
        #expect(SupabaseConfig.from(info: info) == nil)
    }

    @Test
    func oneValueAloneIsNotEnough() {
        #expect(SupabaseConfig.from(info: ["SupabaseURL": address]) == nil)
        #expect(SupabaseConfig.from(info: ["SupabaseURL": address, "SupabaseAnonKey": ""]) == nil)
    }

    /// The key travels with every request; not over plain HTTP.
    @Test
    func onlyHTTPSIsAccepted() {
        let info = ["SupabaseURL": "http://abcdefghijklmnop.supabase.co", "SupabaseAnonKey": key]
        #expect(SupabaseConfig.from(info: info) == nil)
    }
}
