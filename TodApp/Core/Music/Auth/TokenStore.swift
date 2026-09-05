import Foundation
import Security

/// Where the refresh token lives between launches. The access token is
/// deliberately not stored: it is short-lived and cheap to fetch again.
protocol TokenStore: Sendable {
    func read() throws -> String?
    func write(_ refreshToken: String) throws
    func clear() throws
}

/// The Keychain for secure storage: the token is encrypted at rest and not
/// readable from a file backup the way UserDefaults would be.
struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String

    init(service: String = "com.lennetschierhorn.TodApp", account: String = "spotify-refresh-token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TodAppError.tokenStorageFailed
        }
        return String(decoding: data, as: UTF8.self)
    }

    func write(_ refreshToken: String) throws {
        // Delete first: SecItemAdd on an existing item fails with
        // errSecDuplicateItem, and an update needs a different call shape.
        let deleteStatus = SecItemDelete(query as CFDictionary)
        // errSecSuccess means an old item was removed; errSecItemNotFound means
        // there was none to remove, which is the normal case on a first write.
        // Anything else is a real Keychain failure, and swallowing it here would
        // resurface later as a confusing duplicate-item error from SecItemAdd.
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw TodAppError.tokenStorageFailed
        }
        var item = query
        item[kSecValueData as String] = Data(refreshToken.utf8)
        // After a reboot this item stays out of reach until the device has been
        // unlocked once; from then on it is readable even while locked again,
        // which is what lets a background refresh reach it. "ThisDeviceOnly"
        // keeps it out of backups that could be restored onto another device --
        // a refresh token is a bearer credential, and whoever holds it acts as
        // this user until it is revoked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw TodAppError.tokenStorageFailed
        }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TodAppError.tokenStorageFailed
        }
    }
}

/// Stands in for the Keychain in tests, which have no entitlements.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(stored: String? = nil) {
        self.stored = stored
    }

    func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func write(_ refreshToken: String) throws {
        lock.lock(); defer { lock.unlock() }
        stored = refreshToken
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
