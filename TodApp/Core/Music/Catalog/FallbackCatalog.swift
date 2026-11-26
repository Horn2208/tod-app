import Foundation

/// Asks one catalog and, when that one cannot answer, another.
///
/// MusicKit is the better catalog, but it answers only once the developer
/// account's MusicKit service is switched on and the listener has allowed
/// Apple Music -- until then every request throws. Falling back on a throw,
/// and only on a throw, keeps the open iTunes catalog playing previews in the
/// meantime, without letting that weaker search overrule a MusicKit answer
/// that simply found nothing.
struct FallbackCatalog: MusicCatalog {
    let primary: any MusicCatalog
    let fallback: any MusicCatalog
    /// Whether the primary is worth asking at all right now.
    let usesPrimary: @Sendable () -> Bool

    func search(title: String, artist: String) async throws -> [CatalogSong] {
        try await ask { try await $0.search(title: title, artist: artist) }
    }

    func song(id: String) async throws -> CatalogSong? {
        try await ask { try await $0.song(id: id) }
    }

    func song(isrc: String) async throws -> CatalogSong? {
        try await ask { try await $0.song(isrc: isrc) }
    }

    private func ask<Answer>(_ question: (any MusicCatalog) async throws -> Answer) async throws -> Answer {
        guard usesPrimary() else { return try await question(fallback) }
        do {
            return try await question(primary)
        } catch {
            return try await question(fallback)
        }
    }
}
