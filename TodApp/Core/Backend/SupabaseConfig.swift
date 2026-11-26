import Foundation
import os

/// Where the app's Supabase project lives, as the build wrote it into the
/// Info.plist from `Config/Secrets.xcconfig`.
///
/// That file stays out of git. A build without it carries empty values -- or,
/// depending on how it was built, the unexpanded `$(SUPABASE_URL)` -- and then
/// there is no backend: the app keeps running on its in-memory data.
///
/// The key is the public client key (publishable, or the legacy anon key).
/// What it may reach is decided by row level security on the server, not by
/// keeping it hidden in the app.
struct SupabaseConfig: Equatable, Sendable {
    let url: URL
    let anonKey: String

    static func from(info: [String: Any]) -> SupabaseConfig? {
        guard let address = info["SupabaseURL"] as? String,
              let key = info["SupabaseAnonKey"] as? String,
              !address.isEmpty, !key.isEmpty,
              // A build setting that was never defined stays as its own name.
              !address.contains("$("), !key.contains("$("),
              let url = URL(string: address),
              url.scheme == "https", url.host() != nil
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }

    /// This build's project, if it was built with one.
    static var bundled: SupabaseConfig? {
        from(info: Bundle.main.infoDictionary ?? [:])
    }

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "backend")

    /// Says once at launch which project this build talks to -- the host,
    /// never the key -- so a build that lost its secrets file shows it.
    static func reportOnLaunch() {
        if let bundled {
            log.notice("supabase \(bundled.url.host() ?? "?", privacy: .public)")
        } else {
            log.notice("no supabase config, in-memory data")
        }
    }
}
