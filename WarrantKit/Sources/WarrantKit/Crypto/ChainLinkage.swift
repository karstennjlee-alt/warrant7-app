import Foundation

/// How the previous hash is fed into `SHA256(previous_hash || canonical)`.
///
/// The two implementations — this one and the gateway's — must agree byte for byte or every
/// honest record reads as forged. Until the web implementation is confirmed, ``rawBytes`` is
/// the default and this enum is the single place to change it.
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
    /// Signature is over the canonical JSON bytes of the record body.
    case canonicalBody
}

/// The wire-format decisions that must match the gateway, gathered in one struct so a
/// mismatch is one edit to fix rather than a hunt.
public struct ChainFormat: Sendable, Hashable {
    public let linkage: ChainLinkage
    public let signaturePayload: SignaturePayload
    public let envelopeKeys: Set<String>

    public init(
        linkage: ChainLinkage = .rawBytes,
        signaturePayload: SignaturePayload = .digestBytes,
        envelopeKeys: Set<String> = ReceiptRecord.envelopeKeys
    ) {
        self.linkage = linkage
        self.signaturePayload = signaturePayload
        self.envelopeKeys = envelopeKeys
    }

    public static let `default` = ChainFormat()
}
