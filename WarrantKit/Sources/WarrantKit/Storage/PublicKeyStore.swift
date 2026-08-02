import CryptoKit
import Foundation

/// Holds the organization's Ed25519 **public** key.
///
/// This is the asymmetry that makes the phone an independent verifier: it can check that the
/// gateway signed a record, and it cannot produce such a signature itself. If a private
/// signing key ever appears in this file, the product's central claim has been broken.
public struct PublicKeyStore: Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func store(base64: String) throws {
        guard Data(base64Encoded: base64)?.count == 32 else { throw Failure.notAnEd25519Key }
        try keychain.setString(base64, for: KeychainStore.Account.orgPublicKey)
    }

    public func base64() throws -> String? {
        try keychain.string(for: KeychainStore.Account.orgPublicKey)
    }

    public func key() throws -> Curve25519.Signing.PublicKey? {
        guard let base64 = try base64(), let data = Data(base64Encoded: base64) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    }

    public func clear() throws {
        try keychain.removeItem(for: KeychainStore.Account.orgPublicKey)
    }

    /// Grouped into fours so two people can read a key aloud to each other and actually
    /// compare it — which is the point of showing it at all.
    public static func readable(_ base64: String) -> String {
        stride(from: 0, to: base64.count, by: 4).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(4, base64.count - offset))
            return String(base64[start..<end])
        }.joined(separator: " ")
    }

    public enum Failure: Error, Equatable, Sendable {
        case notAnEd25519Key

        public var message: String {
            "That isn't an Ed25519 public key. It should be 32 bytes, base64 encoded."
        }
    }
}
