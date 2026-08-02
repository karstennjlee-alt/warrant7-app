import CryptoKit
import Foundation

/// What the device concluded about one record. Nothing here is reported by a server.
public enum RecordVerdict: Sendable, Hashable {
    /// Digest recomputed, link matched, signature valid under the supplied public key.
    case ok
    /// The record does not hash to the digest stored alongside it.
    case digestMismatch(recomputed: Digest256, stored: Digest256)
    /// The record's `prev` does not name the digest of the record before it.
    case brokenLink(expected: Digest256, stored: Digest256)
    /// Ed25519 said no.
    case badSignature
    /// The record itself checks out, but it sits after a break, so it proves nothing.
    case untrusted
    /// The record is missing a field verification needs.
    case malformed(String)

    public var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

public struct RecordVerification: Sendable, Hashable {
    public let sequence: Int
    public let event: String
    public let verdict: RecordVerdict
}

public struct ChainVerification: Sendable, Hashable {
    public let records: [RecordVerification]
    /// Index of the first record that failed, if any. Everything after it is `.untrusted`.
    public let firstFailureIndex: Int?

    public var isVerified: Bool { firstFailureIndex == nil }
}

/// What the signature covers. The server's choice here is a wire-format decision, so it is a
/// parameter rather than a constant baked into the verifier.
public enum SignaturePayload: Sendable, Hashable {
    /// Signature is over the 32 raw digest bytes.
    case digestBytes
    /// Signature is over the canonical JSON bytes of the record body.
    case canonicalBody
}

/// Verifies a hash-linked, Ed25519-signed receipt chain on-device, from an exported bundle and
/// a public key, with no network access and no trust in whatever produced the bundle.
///
/// The claim this supports, stated exactly: the receipts can be edited, but they cannot be
/// edited without verification failing here.
public struct ChainVerifier: Sendable {

    /// Members of a record that are envelope, not body, and so are excluded before hashing.
    public let envelopeKeys: Set<String>
    public let signaturePayload: SignaturePayload

    public init(
        envelopeKeys: Set<String> = ["digest", "signature"],
        signaturePayload: SignaturePayload = .digestBytes
    ) {
        self.envelopeKeys = envelopeKeys
        self.signaturePayload = signaturePayload
    }

    /// - Parameters:
    ///   - records: the chain in sequence order, each a JSON object carrying at least
    ///     `seq`, `prev`, `digest` and `signature`.
    ///   - publicKey: the organization's Ed25519 public key, held on the device.
    public func verify(records: [JSONValue], publicKey: Curve25519.Signing.PublicKey) -> ChainVerification {
        var results: [RecordVerification] = []
        var expectedPrevious = Digest256.genesis
        var firstFailureIndex: Int?

        for (index, record) in records.enumerated() {
            let sequence = Int(record["seq"]?.numberValue ?? Double(index + 1))
            let event = record["event"]?.stringValue ?? "—"

            if firstFailureIndex != nil {
                results.append(RecordVerification(sequence: sequence, event: event, verdict: .untrusted))
                continue
            }

            let verdict = verdict(for: record, expectedPrevious: expectedPrevious, publicKey: publicKey)
            results.append(RecordVerification(sequence: sequence, event: event, verdict: verdict))

            if verdict.isOK, let stored = record["digest"]?.stringValue, let digest = Digest256(hex: stored) {
                expectedPrevious = digest
            } else {
                firstFailureIndex = index
            }
        }

        return ChainVerification(records: results, firstFailureIndex: firstFailureIndex)
    }

    private func verdict(
        for record: JSONValue,
        expectedPrevious: Digest256,
        publicKey: Curve25519.Signing.PublicKey
    ) -> RecordVerdict {
        guard let storedDigestHex = record["digest"]?.stringValue,
              let storedDigest = Digest256(hex: storedDigestHex) else {
            return .malformed("digest")
        }
        guard let previousHex = record["prev"]?.stringValue,
              let previous = Digest256(hex: previousHex) else {
            return .malformed("prev")
        }
        guard let signatureBase64 = record["signature"]?.stringValue,
              let signature = Data(base64Encoded: signatureBase64) else {
            return .malformed("signature")
        }

        guard previous == expectedPrevious else {
            return .brokenLink(expected: expectedPrevious, stored: previous)
        }

        let body = record.removingKeys(envelopeKeys)
        guard let recomputed = try? Digest256.of(body) else {
            return .malformed("body")
        }
        guard recomputed == storedDigest else {
            return .digestMismatch(recomputed: recomputed, stored: storedDigest)
        }

        let signed: Data
        switch signaturePayload {
        case .digestBytes:
            signed = recomputed.bytes
        case .canonicalBody:
            guard let bytes = try? CanonicalJSON.canonicalBytes(body) else { return .malformed("body") }
            signed = bytes
        }
        guard publicKey.isValidSignature(signature, for: signed) else {
            return .badSignature
        }
        return .ok
    }
}
