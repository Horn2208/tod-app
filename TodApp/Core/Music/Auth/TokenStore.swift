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
        // Update-in-place, not delete-then-add: if this throws, the query
        // above still matches whatever was stored before, byte for byte -- a
        // failed write leaves the previous refresh token intact rather than
        // losing it. (The old shape deleted the working token first and only
        // then tried to add the new one, so a failed add lost it for good --
        // a user who was already signed in would silently lose their session
        // the moment the next Keychain operation failed for any reason.)
        var attributes: [String: Any] = [
            kSecValueData as String: Data(refreshToken.utf8)
        ]
        // After a reboot this item stays out of reach until the device has been
        // unlocked once; from then on it is readable even while locked again,
        // which is what lets a background refresh reach it. "ThisDeviceOnly"
        // keeps it out of backups that could be restored onto another device --
        // a refresh token is a bearer credential, and whoever holds it acts as
        // this user until it is revoked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        // errSecItemNotFound means there was nothing to update -- the normal
        // case on a first write -- so fall through to adding it instead.
        // Anything else is a genuine Keychain failure, and because this was
        // an update attempt, whatever was stored before is untouched.
        guard updateStatus == errSecItemNotFound else {
            throw TodAppError.tokenStorageFailed
        }

        var item = query
        item.merge(attributes) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            // Nothing existed before this call (that is why the update above
            // reported errSecItemNotFound rather than succeeding), so there
            // is nothing to lose here -- this just leaves the account signed
            // out, same as before the write was attempted.
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
