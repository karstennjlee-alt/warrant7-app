import CryptoKit
import Foundation

/// A SHA-256 digest, kept as raw bytes and rendered as lowercase hex only at the edges.
public struct Digest256: Sendable, Hashable, CustomStringConvertible {
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    public init?(hex: String) {
        guard let bytes = Data(hexEncoded: hex), bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    /// The all-zero digest that a hash chain starts from.
    public static let genesis = Digest256(bytes: Data(repeating: 0, count: 32))!

    /// Hash the RFC 8785 canonical form of a JSON value.
    public static func of(_ value: JSONValue) throws -> Digest256 {
        Digest256(bytes: Data(SHA256.hash(data: try CanonicalJSON.canonicalBytes(value))))!
    }

    public static func of(_ data: Data) -> Digest256 {
        Digest256(bytes: Data(SHA256.hash(data: data)))!
    }

    public var hex: String { bytes.hexEncoded }

    /// Head and tail, for a card that must stay readable on a phone. Tap reveals ``hex``.
    public var truncated: String {
        "\(hex.prefix(12))…\(hex.suffix(6))"
    }

    public var description: String { hex }
}

public extension Data {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexEncoded hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}
