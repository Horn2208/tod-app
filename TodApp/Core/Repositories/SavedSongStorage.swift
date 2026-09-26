import Foundation

/// Where noted songs (`SavedSong`) are kept: on this phone, one list per
/// account, so a phone handed on does not show someone else's.
protocol SavedSongStorage {
    func load(for userID: String) throws -> [SavedSong]
    func save(_ songs: [SavedSong], for userID: String) throws
    /// Forgets the account's list, when the account itself is deleted.
    func delete(for userID: String) throws
}

/// One JSON file per account, in Application Support. The list is small --
/// a handful of songs -- so it is read and written whole.
struct FileSavedSongStorage: SavedSongStorage {
    let directory: URL

    /// The app's own: `Application Support/SavedSongs`.
    static func applicationSupport() -> FileSavedSongStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileSavedSongStorage(directory: base.appendingPathComponent("SavedSongs", isDirectory: true))
    }

    func load(for userID: String) throws -> [SavedSong] {
        let url = file(for: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.decoder.decode([SavedSong].self, from: Data(contentsOf: url))
    }

    func save(_ songs: [SavedSong], for userID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(songs).write(to: file(for: userID), options: .atomic)
    }

    func delete(for userID: String) throws {
        let url = file(for: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// The account id as a file name, with anything but letters, digits and
    /// dashes taken out: an id is a uuid, but a file name is no place to
    /// find out it was not.
    func file(for userID: String) -> URL {
        let safe = String(userID.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-"
        }.map(Character.init))
        return directory.appendingPathComponent("\(safe.isEmpty ? "local" : safe).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// For tests and previews: kept in memory, per account, for as long as the
/// object lives.
final class InMemorySavedSongStorage: SavedSongStorage {
    private var lists: [String: [SavedSong]] = [:]

    func load(for userID: String) throws -> [SavedSong] { lists[userID] ?? [] }
    func save(_ songs: [SavedSong], for userID: String) throws { lists[userID] = songs }
    func delete(for userID: String) throws { lists[userID] = nil }
}
