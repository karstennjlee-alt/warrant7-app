import Testing
import Foundation
@testable import WarrantKit

/// warrant7 is a separate implementation by a separate author, and it signs its ledger
/// differently from ours in three ways at once:
///
///   envelope  = {org_id, sequence, event_type, payload}  — `previous_hash` is not inside it
///   hash      = SHA-256( utf8(previous_hash_hex) ‖ canonical(envelope) )
///   signature = Ed25519 over utf8(record_hash_hex)       — the hex string, not the 32 bytes
///   key       = hex rather than base64
///
/// None of that was documented in a way I could rely on; it was determined by testing which
/// combination reproduced a live record's hash and validated its signature. This suite pins the
/// answer, against a bundle exported from production.
///
/// It matters because the failure is silent and looks like an accusation: verify someone else's
/// perfectly good evidence with our conventions and the app calls their records forged.
@Suite("warrant7 interop")
struct Warrant7InteropTests {

    static func bundle() throws -> EvidenceBundle {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "warrant7-bundle", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "warrant7-bundle", withExtension: "json")
        #else
        let url = Bundle(for: GoldenVectorTests.FixtureToken.self).url(forResource: "warrant7-bundle", withExtension: "json")
        #endif
        guard let url else { throw Failure.missing }
        return try EvidenceBundle.parse(try Data(contentsOf: url))
    }

    enum Failure: Error { case missing }

    @Test("A production warrant7 ledger verifies on the device")
    func productionLedgerVerifies() throws {
        let bundle = try Self.bundle()
        let report = ChainVerifier().verify(bundle: bundle)

        #expect(report.isVerified, "warrant7's own evidence must not read as forged — \(report.summary)")
        #expect(report.records.count == bundle.records.count)
        #expect(bundle.records.count > 1, "a one-record chain would not exercise the linkage")
    }

    @Test("The dialect is taken from the bundle, not assumed")
    func dialectIsDetected() throws {
        let bundle = try Self.bundle()
        #expect(bundle.format == "warrant7.evidence.v1")

        let resolved = ChainFormat.detected(from: bundle)
        #expect(resolved == .warrant7)
        #expect(resolved.linkage == .hexASCII)
        #expect(resolved.signaturePayload == .digestHexUTF8)
        #expect(resolved.keyEncoding == .hex)
    }

    @Test("A hex public key is normalised so everything downstream sees one encoding")
    func hexKeyNormalised() throws {
        let bundle = try Self.bundle()
        let decoded = Data(base64Encoded: bundle.publicKeyBase64)
        #expect(decoded?.count == 32)
    }

    @Test("warrant7's field names decode into the model")
    func fieldNamesDecode() throws {
        let bundle = try Self.bundle()
        let records = bundle.parsedRecords

        #expect(records.count == bundle.records.count, "sequence/event_type/record_hash all resolved")
        #expect(records.first?.sequence == 1)
        #expect(records.first?.event.isEmpty == false)
    }

    /// The same guarantee, against someone else's ledger: edit it and the device says so.
    @Test("An edited warrant7 record fails at the record that changed")
    func tamperedProductionLedgerFails() throws {
        let bundle = try Self.bundle()
        var records = bundle.records
        guard case .object(var members) = records[0] else { return }
        members["payload"] = .string("edited")
        records[0] = .object(members)

        let report = ChainVerifier().verify(bundle: EvidenceBundle(
            organization: bundle.organization,
            exportedAt: bundle.exportedAt,
            publicKeyBase64: bundle.publicKeyBase64,
            records: records,
            format: bundle.format
        ))

        #expect(!report.isVerified)
        #expect(report.firstFailure == 1)
        #expect(!report.isKeyMismatch, "an edit is not a key problem")
    }

    /// Our own bundles must keep verifying under the default dialect — detection must not
    /// quietly re-point everything at warrant7's rules.
    @Test("Detection does not disturb our own format")
    func ownFormatUnaffected() async throws {
        let source = DemoDataSource(keychain: KeychainStore(service: "test.\(UUID().uuidString)"))
        let ours = try await source.exportBundle()

        #expect(ours.format == nil, "our own bundles make no dialect claim")
        #expect(ChainFormat.detected(from: ours) == .default)
        #expect(ChainVerifier().verify(bundle: ours).isVerified, "detection must not break our own ledger")
    }
}
