import Foundation

/// How the previous hash is fed into `SHA-256(previous_hash ‖ canonical)`.
///
/// The two implementations — this one and the gateway's — must agree byte for byte or every
/// honest record reads as forged.
public enum ChainLinkage: String, Sendable, Hashable, CaseIterable {
    /// Concatenate the 32 raw bytes of the previous digest.
    case rawBytes
    /// Concatenate the 64 lowercase ASCII hex characters of the previous digest.
    case hexASCII
}

/// What an Ed25519 signature covers.
public enum SignaturePayload: String, Sendable, Hashable, CaseIterable {
    /// Signature is over the 32 raw bytes of the record's own digest.
    case digestBytes
    /// Signature is over the 64 ASCII hex characters of the digest.
    ///
    /// Not equivalent to ``digestBytes`` — it signs a different 64-byte message — and the
    /// difference is invisible until a signature fails to verify.
    case digestHexUTF8
    /// Signature is over the canonical JSON bytes of the record body.
    case canonicalBody
}

/// How a public key is written down.
public enum PublicKeyEncoding: String, Sendable, Hashable, CaseIterable {
    case base64
    case hex
}

/// What a record's members are called.
///
/// Every implementation of this idea picks its own names — `seq` or `sequence`, `event` or
/// `event_type`, `hash` or `record_hash` — and a verifier that hard-codes one set can only ever
/// check its own author's work.
public struct RecordFieldNames: Sendable, Hashable {
    public let sequence: String
    public let event: String
    public let previousHash: String
    public let hash: String
    public let signature: String
    public let amountMinor: String
    public let currency: String
    public let timestamp: String
    public let actor: String
    public let resource: String

    public init(
        sequence: String = "seq",
        event: String = "event",
        previousHash: String = "prev",
        hash: String = "hash",
        signature: String = "signature",
        amountMinor: String = "amount_minor",
        currency: String = "currency",
        timestamp: String = "ts",
        actor: String = "actor",
        resource: String = "resource"
    ) {
        self.sequence = sequence
        self.event = event
        self.previousHash = previousHash
        self.hash = hash
        self.signature = signature
        self.amountMinor = amountMinor
        self.currency = currency
        self.timestamp = timestamp
        self.actor = actor
        self.resource = resource
    }

    /// The dialect warrant7 speaks.
    public static let warrant7 = RecordFieldNames(
        sequence: "sequence",
        event: "event_type",
        previousHash: "previous_hash",
        hash: "record_hash",
        signature: "signature",
        timestamp: "created_at"
    )
}

/// Every decision that has to match whoever produced the ledger, gathered in one place so a
/// mismatch is one edit to fix rather than a hunt.
public struct ChainFormat: Sendable, Hashable {
    public let linkage: ChainLinkage
    public let signaturePayload: SignaturePayload
    public let keyEncoding: PublicKeyEncoding
    public let fields: RecordFieldNames
    /// Members excluded from the body before hashing.
    public let envelopeKeys: Set<String>

    public init(
        linkage: ChainLinkage = .rawBytes,
        signaturePayload: SignaturePayload = .digestBytes,
        keyEncoding: PublicKeyEncoding = .base64,
        fields: RecordFieldNames = RecordFieldNames(),
        envelopeKeys: Set<String> = ["hash", "signature"]
    ) {
        self.linkage = linkage
        self.signaturePayload = signaturePayload
        self.keyEncoding = keyEncoding
        self.fields = fields
        self.envelopeKeys = envelopeKeys
    }

    /// The local gateway in `gateway/`: raw-byte linkage, signatures over the digest bytes,
    /// `prev` hashed as part of the body.
    public static let `default` = ChainFormat()

    /// warrant7, determined empirically from a live export rather than from its documentation:
    ///
    ///   envelope  = {org_id, sequence, event_type, payload}   — `previous_hash` is *not* inside it
    ///   hash      = SHA-256( utf8(previous_hash_hex) ‖ canonical(envelope) )
    ///   signature = Ed25519 over utf8(record_hash_hex)
    ///   key       = hex
    ///
    /// Three independent places to get wrong, and each one fails the same way: a real receipt
    /// that looks tampered with.
    public static let warrant7 = ChainFormat(
        linkage: .hexASCII,
        signaturePayload: .digestHexUTF8,
        keyEncoding: .hex,
        fields: .warrant7,
        envelopeKeys: ["previous_hash", "record_hash", "signature"]
    )

    /// Picks the dialect from a bundle's own self-description, falling back to this app's.
    public static func detected(from bundle: EvidenceBundle) -> ChainFormat {
        bundle.format?.hasPrefix("warrant7") == true ? .warrant7 : .default
    }
}
