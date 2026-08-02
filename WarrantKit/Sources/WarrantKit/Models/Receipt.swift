import Foundation

/// One record in the signed ledger.
///
/// `body` is held as ``JSONValue`` rather than as typed fields on purpose: the device must be
/// able to recompute the digest over *exactly* what was signed, including any field this
/// version of the app does not know about. Decoding into a struct and re-encoding would
/// silently drop unknown members and every digest would stop matching.
public struct ReceiptRecord: Sendable, Hashable, Identifiable {
    public let sequence: Int
    public let event: String
    public let actor: String
    public let resource: String
    public let amount: Money?
    public let timestamp: Date

    /// Envelope: excluded from the body before hashing.
    public let previousHash: String
    public let hash: String
    public let signature: String

    /// Exactly the members that were hashed.
    public let body: JSONValue
    /// The record as received, envelope included.
    public let raw: JSONValue

    public var id: Int { sequence }

    /// Members that are envelope rather than content. Everything else is hashed.
    public static let envelopeKeys: Set<String> = ["hash", "signature"]

    public init?(raw: JSONValue) {
        guard case .object = raw,
              let sequence = raw["seq"]?.numberValue.map({ Int($0) }),
              let event = raw["event"]?.stringValue,
              let previousHash = raw["prev"]?.stringValue,
              let hash = raw["hash"]?.stringValue,
              let signature = raw["signature"]?.stringValue
        else { return nil }

        self.sequence = sequence
        self.event = event
        self.actor = raw["actor"]?.stringValue ?? "—"
        self.resource = raw["resource"]?.stringValue ?? "—"
        self.previousHash = previousHash
        self.hash = hash
        self.signature = signature
        self.raw = raw
        self.body = raw.removingKeys(Self.envelopeKeys)

        if let minor = raw["amount_minor"]?.numberValue {
            self.amount = Money(
                minorUnits: Int(minor),
                currencyCode: raw["currency"]?.stringValue ?? "USD"
            )
        } else {
            self.amount = nil
        }

        if let ts = raw["ts"]?.stringValue, let parsed = WarrantJSON.date(from: ts) {
            self.timestamp = parsed
        } else {
            self.timestamp = Date(timeIntervalSince1970: 0)
        }
    }

    /// Whether this record *records* a negative outcome. Distinct from being broken evidence —
    /// see the legend in §5.4. A denial is valid evidence; a bad digest is not evidence at all.
    public var isNegativeOutcome: Bool {
        ["DENIED", "BLOCKED", "EXPIRED", "FAILED"].contains(event.uppercased())
    }

    public var hashShort: String {
        guard hash.count > 20 else { return hash }
        return "\(hash.prefix(12))…\(hash.suffix(6))"
    }
}

/// What `GET /api/v1/receipts/export` returns, and what the Verify tab imports from a QR
/// code, a file, the clipboard, or AirDrop.
public struct EvidenceBundle: Sendable, Hashable {
    public let organization: String
    public let exportedAt: Date?
    /// Base64 Ed25519 public key, 32 raw bytes.
    public let publicKeyBase64: String
    public let records: [JSONValue]

    public init(organization: String, exportedAt: Date?, publicKeyBase64: String, records: [JSONValue]) {
        self.organization = organization
        self.exportedAt = exportedAt
        self.publicKeyBase64 = publicKeyBase64
        self.records = records
    }

    public enum ImportFailure: Error, Equatable, Sendable {
        case notJSON
        case missingRecords
        case missingPublicKey

        /// §9.5: no stack traces, no raw codes, no "Error:".
        public var message: String {
            switch self {
            case .notJSON: "That doesn't look like an evidence bundle. Try exporting it again."
            case .missingRecords: "This bundle has no records in it."
            case .missingPublicKey: "This bundle has no public key. Paste one to verify against."
            }
        }
    }

    public static func parse(_ data: Data) throws -> EvidenceBundle {
        guard let root = try? JSONValue.parse(data) else { throw ImportFailure.notJSON }

        guard case .array(let records)? = root["records"] ?? root["receipts"], !records.isEmpty else {
            throw ImportFailure.missingRecords
        }
        guard let key = root["public_key"]?.stringValue ?? root["publicKey"]?.stringValue else {
            throw ImportFailure.missingPublicKey
        }

        return EvidenceBundle(
            organization: root["org"]?.stringValue ?? root["organization"]?.stringValue ?? "—",
            exportedAt: root["exported_at"]?.stringValue.flatMap(WarrantJSON.date(from:)),
            publicKeyBase64: key,
            records: records
        )
    }

    public var parsedRecords: [ReceiptRecord] {
        records.compactMap(ReceiptRecord.init(raw:))
    }
}

/// Shared JSON conventions, so the wire format is defined in exactly one place.
public enum WarrantJSON {
    public static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let parsed = date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "not an ISO 8601 timestamp"
                )
            }
            return parsed
        }
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }
}
