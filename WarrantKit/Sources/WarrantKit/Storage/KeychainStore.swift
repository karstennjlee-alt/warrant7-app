import Foundation
import Security

/// Keychain-backed storage for the two things the device is allowed to hold: a session token
/// and the organization's *public* key. No provider credential, no service-role key, and no
/// signing private key ever passes through here.
///
/// Everything is written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable to a
/// background refresh after the first unlock, never present in a backup, never on another device.
public struct KeychainStore: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case malformedData
    }

    public let service: String

    public init(service: String = "app.warrant.ios") {
        self.service = service
    }

    public func set(_ data: Data, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let insertStatus = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw Failure.unexpectedStatus(insertStatus) }
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    public func data(for account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Failure.malformedData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    public func removeItem(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.unexpectedStatus(status)
        }
    }

    public func setString(_ string: String, for account: String) throws {
        try set(Data(string.utf8), for: account)
    }

    public func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw Failure.malformedData }
        return string
    }
}

public extension KeychainStore {
    enum Account {
        public static let sessionToken = "session-token"
        public static let refreshToken = "refresh-token"
        public static let orgPublicKey = "org-public-key"
        public static let signedInEmail = "signed-in-email"
    }
}
