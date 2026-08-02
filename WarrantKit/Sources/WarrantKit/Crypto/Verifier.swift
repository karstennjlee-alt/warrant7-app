import CryptoKit
import Foundation

/// The verdict on one record. Every failure mode gets its own code and its own sentence —
/// never one generic red (§5.4), because "this record was altered" and "this record is fine
/// but sits after one that was" are completely different facts about your evidence.
public enum VerificationCode: Sendable, Hashable {
    case ok
    /// A field was altered, or the signature was produced by a different key.
    case signatureInvalid
    /// The stored hash disagrees with the recomputation, though the signature still checks out.
    case hashMismatch
    /// `prev` does not name the record before it — records were reordered.
    case chainBroken
    /// A sequence number is missing — a record was deleted.
    case sequenceGap
    /// Every record fails signature while hashes and links are intact: wrong public key.
    case keyMismatch
    /// Structurally not a record.
    case malformed(String)
    /// This record verifies on its own but depends on one that failed.
    case untrusted(dependsOn: Int)

    public var isOK: Bool {
        if case .ok = self { return true }
        return false
    }

    /// Mono, uppercase — a system-computed string (§8).
    public var label: String {
        switch self {
        case .ok: "OK"
        case .signatureInvalid: "SIGNATURE_INVALID"
        case .hashMismatch: "HASH_MISMATCH"
        case .chainBroken: "CHAIN_BROKEN"
        case .sequenceGap: "SEQUENCE_GAP"
        case .keyMismatch: "KEY_MISMATCH"
        case .malformed: "MALFORMED"
        case .untrusted(let n): "UNTRUSTED_DEPENDS_ON_\(n)"
        }
    }

    /// Public Sans — written by a person, for a person.
    public var message: String {
        switch self {
        case .ok:
            "Recomputed and signed correctly."
        case .signatureInvalid:
            "This record was altered after it was signed. The signature no longer matches its contents."
        case .hashMismatch:
            "The stored hash doesn't match a recomputation of this record."
        case .chainBroken:
            "This record doesn't follow the one before it. The records have been reordered."
        case .sequenceGap:
            "A record is missing here. The sequence skips a number."
        case .keyMismatch:
            "Nothing verifies under this public key. It's the wrong key for this bundle, not proof the records were altered."
        case .malformed(let field):
            "This record is missing its \(field), so there's nothing to check."
        case .untrusted(let n):
            "Can't be trusted: it depends on record \(n), which failed."
        }
    }
}

public struct RecordReport: Sendable, Hashable, Identifiable {
    public let sequence: Int
    public let event: String
    public let code: VerificationCode
    public var id: Int { sequence }
    public var isOK: Bool { code.isOK }
}

public struct VerificationReport: Sendable, Hashable {
    public let records: [RecordReport]
    /// Sequence number of the first record that failed, if any.
    public let firstFailure: Int?
    /// True when the bundle is intact but the key is wrong — a materially different claim
    /// from "this evidence was tampered with", and worth saying out loud.
    public let isKeyMismatch: Bool

    public var isVerified: Bool { firstFailure == nil && !isKeyMismatch }

    public var summary: String {
        if isKeyMismatch {
            return "Nothing verified under this key."
        }
        if let first = firstFailure {
            return "Record \(first) failed. Everything after it is untrusted."
        }
        return "\(records.count) record\(records.count == 1 ? "" : "s") verified."
    }
}

/// Verifies a hash-linked, Ed25519-signed ledger on-device, from a bundle and a public key,
/// with no network access and no trust in whatever produced the bundle.
///
/// The claim this supports, stated exactly: the receipts can be edited, but they cannot be
/// secretly edited without verification failing here.
public struct ChainVerifier: Sendable {
    public let format: ChainFormat

    public init(format: ChainFormat = .default) {
        self.format = format
    }

    /// Verifies a bundle in whatever dialect it declares, rather than only in this app's.
    public func verify(bundle: EvidenceBundle) -> VerificationReport {
        // A bundle that names its own format gets checked on its own terms. Insisting on our
        // conventions would report someone else's perfectly good evidence as forged.
        let resolved = self.format == .default ? ChainFormat.detected(from: bundle) : self.format
        if resolved != self.format {
            return ChainVerifier(format: resolved).verify(bundle: bundle)
        }

        guard let keyData = Data(base64Encoded: bundle.publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            let records = bundle.records.enumerated().map { index, raw in
                RecordReport(
                    sequence: raw[format.fields.sequence]?.numberValue.map { Int($0) } ?? index + 1,
                    event: raw[format.fields.event]?.stringValue ?? "—",
                    code: .malformed("public key")
                )
            }
            return VerificationReport(records: records, firstFailure: records.first?.sequence, isKeyMismatch: false)
        }
        return verify(records: bundle.records, publicKey: key)
    }

    public func verify(records rawRecords: [JSONValue], publicKey: Curve25519.Signing.PublicKey) -> VerificationReport {
        // Structural pass. A record that will not parse cannot be checked at all.
        var parsed: [ReceiptRecord] = []
        for (index, raw) in rawRecords.enumerated() {
            guard let record = ReceiptRecord(raw: raw, format: format) else {
                let sequence = raw[format.fields.sequence]?.numberValue.map { Int($0) } ?? index + 1
                var reports = parsed.map { RecordReport(sequence: $0.sequence, event: $0.event, code: .ok) }
                reports.append(RecordReport(sequence: sequence, event: raw[format.fields.event]?.stringValue ?? "—", code: .malformed("envelope")))
                for later in rawRecords.dropFirst(index + 1) {
                    reports.append(RecordReport(
                        sequence: later[format.fields.sequence]?.numberValue.map { Int($0) } ?? 0,
                        event: later[format.fields.event]?.stringValue ?? "—",
                        code: .untrusted(dependsOn: sequence)
                    ))
                }
                return VerificationReport(records: reports, firstFailure: sequence, isKeyMismatch: false)
            }
            parsed.append(record)
        }
        guard !parsed.isEmpty else {
            return VerificationReport(records: [], firstFailure: nil, isKeyMismatch: false)
        }

        // Sequence pass, run before any cryptography so a deletion and a reordering get
        // different answers. A deletion leaves a hole in the range; a reordering does not.
        if let sequenceFailure = sequenceFailure(in: parsed) {
            return report(parsed, failingAt: sequenceFailure.index, code: sequenceFailure.code)
        }

        // Wrong-key pass, before the sequential one.
        //
        // It has to run first and independently. In the sequential pass a failure stops the
        // chain from advancing, so record 2 onwards would report CHAIN_BROKEN and the "every
        // signature failed" shape would never appear. A bundle whose links are all sound but
        // whose signatures all fail is not evidence of tampering — it is the wrong key, and
        // saying "altered" would be a false accusation about someone's evidence.
        if linksAreIntact(parsed), everySignatureFails(parsed, publicKey: publicKey) {
            return VerificationReport(
                records: parsed.map { RecordReport(sequence: $0.sequence, event: $0.event, code: .keyMismatch) },
                firstFailure: parsed.first?.sequence,
                isKeyMismatch: true
            )
        }

        // Cryptographic pass.
        var codes: [VerificationCode] = []
        var expectedPrevious = Digest256.genesis
        var failureIndex: Int?

        for (index, record) in parsed.enumerated() {
            let code = check(record, expectedPrevious: expectedPrevious, publicKey: publicKey)
            codes.append(code)
            if code.isOK {
                expectedPrevious = Digest256(hex: record.hash) ?? .genesis
            } else if failureIndex == nil {
                failureIndex = index
            }
        }

        guard let failureIndex else {
            return VerificationReport(
                records: parsed.map { RecordReport(sequence: $0.sequence, event: $0.event, code: .ok) },
                firstFailure: nil,
                isKeyMismatch: false
            )
        }
        return report(parsed, failingAt: failureIndex, code: codes[failureIndex])
    }

    // MARK: - Per record

    private func check(
        _ record: ReceiptRecord,
        expectedPrevious: Digest256,
        publicKey: Curve25519.Signing.PublicKey
    ) -> VerificationCode {
        guard let previous = Digest256(hex: record.previousHash) else { return .malformed("prev") }
        guard let storedHash = Digest256(hex: record.hash) else { return .malformed("hash") }
        guard let signature = Data(base64Encoded: record.signature) else { return .malformed("signature") }
        guard previous == expectedPrevious else { return .chainBroken }
        guard let canonical = try? CanonicalJSON.canonicalBytes(record.body) else { return .malformed("body") }

        let recomputed = Digest256.chained(previous: previous, canonical: canonical, linkage: format.linkage)

        // Signature is checked against the recomputation, never against the stored hash.
        // Checking it against a value the bundle supplied would be trusting the bundle to
        // report on itself, which is the thing this whole screen exists not to do.
        guard publicKey.isValidSignature(signature, for: signedBytes(for: recomputed, canonical: canonical)) else {
            return .signatureInvalid
        }
        guard recomputed == storedHash else { return .hashMismatch }
        return .ok
    }

    /// Signing the 32 digest bytes and signing their 64 hex characters are different messages,
    /// and nothing about a failure tells you which one the other side meant.
    private func signedBytes(for digest: Digest256, canonical: Data) -> Data {
        switch format.signaturePayload {
        case .digestBytes: digest.bytes
        case .digestHexUTF8: Data(digest.hex.utf8)
        case .canonicalBody: canonical
        }
    }

    // MARK: - Sequence and linkage

    private func sequenceFailure(in records: [ReceiptRecord]) -> (index: Int, code: VerificationCode)? {
        let sequences = records.map(\.sequence)
        guard let low = sequences.min(), let high = sequences.max() else { return nil }

        // A missing number inside the range means a record was removed.
        let present = Set(sequences)
        if present.count < (high - low + 1) {
            let missing = (low...high).first { !present.contains($0) } ?? low
            let index = sequences.firstIndex { $0 > missing } ?? records.count - 1
            return (index, .sequenceGap)
        }
        // Complete range, wrong order: the records were shuffled.
        if let index = zip(sequences, sequences.dropFirst()).enumerated().first(where: { $0.element.1 != $0.element.0 + 1 })?.offset {
            return (index + 1, .chainBroken)
        }
        return nil
    }

    /// True when no record's signature validates. Checked per record against its own
    /// recomputation, so one bad link elsewhere cannot mask the result.
    private func everySignatureFails(
        _ records: [ReceiptRecord],
        publicKey: Curve25519.Signing.PublicKey
    ) -> Bool {
        records.allSatisfy { record in
            guard let previous = Digest256(hex: record.previousHash),
                  let signature = Data(base64Encoded: record.signature),
                  let canonical = try? CanonicalJSON.canonicalBytes(record.body) else { return false }
            let recomputed = Digest256.chained(previous: previous, canonical: canonical, linkage: format.linkage)
            return !publicKey.isValidSignature(signature, for: signedBytes(for: recomputed, canonical: canonical))
        }
    }

    private func linksAreIntact(_ records: [ReceiptRecord]) -> Bool {
        var expected = Digest256.genesis
        for record in records {
            guard let previous = Digest256(hex: record.previousHash), previous == expected,
                  let hash = Digest256(hex: record.hash) else { return false }
            expected = hash
        }
        return true
    }

    private func report(_ records: [ReceiptRecord], failingAt index: Int, code: VerificationCode) -> VerificationReport {
        let failingSequence = records[index].sequence
        let reports = records.enumerated().map { position, record in
            RecordReport(
                sequence: record.sequence,
                event: record.event,
                code: position < index ? .ok
                    : position == index ? code
                    : .untrusted(dependsOn: failingSequence)
            )
        }
        return VerificationReport(records: reports, firstFailure: failingSequence, isKeyMismatch: false)
    }
}
