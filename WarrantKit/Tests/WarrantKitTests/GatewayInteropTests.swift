import Testing
import Foundation
@testable import WarrantKit

/// The test that decides whether this product works on stage.
///
/// Everything else in the suite checks Swift against Swift. These two check Swift against a
/// bundle a *different implementation* produced — the Node gateway in `gateway/`, which
/// canonicalizes, hashes and signs independently. If the two ever disagree about RFC 8785,
/// about `SHA-256(previous_hash ‖ canonical)`, or about what the signature covers, honest
/// evidence starts reading as forged and this is where that shows up.
///
/// Regenerate the fixtures with:
///   cd gateway && node server.mjs &
///   curl -H 'Authorization: Bearer warrant-dev-token' localhost:8787/api/v1/receipts/export
@Suite("Gateway interop")
struct GatewayInteropTests {

    static func bundle(named name: String) throws -> EvidenceBundle {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        #else
        let url = Bundle(for: GoldenVectorTests.FixtureToken.self).url(forResource: name, withExtension: "json")
        #endif
        guard let url else { throw Failure.missing }
        return try EvidenceBundle.parse(try Data(contentsOf: url))
    }

    enum Failure: Error { case missing }

    @Test("A chain the gateway signed verifies on the device")
    func gatewayChainVerifies() throws {
        let bundle = try Self.bundle(named: "gateway-bundle")
        let report = ChainVerifier().verify(bundle: bundle)

        #expect(report.isVerified, "the phone and the gateway disagree — \(report.summary)")
        #expect(report.records.count == bundle.records.count)
        #expect(report.records.filter { !$0.isOK }.isEmpty)
    }

    @Test("The gateway's own field names decode into the model")
    func gatewayRecordsDecode() throws {
        let bundle = try Self.bundle(named: "gateway-bundle")
        let records = bundle.parsedRecords

        #expect(records.count == bundle.records.count, "every record parsed")
        #expect(records.first?.sequence == 1)
        #expect(records.contains { $0.event == "BLOCKED" }, "the hard stop leaves a receipt too")
        // Amounts stay integer minor units all the way across the wire.
        #expect(records.first?.amount?.minorUnits == 12_000)
    }

    /// Editing a stored amount without re-signing is exactly what an administrator with
    /// database access can do. The claim is not that they can't — it is that they cannot do it
    /// quietly.
    @Test("An edited gateway record fails on the device, at the record that changed")
    func tamperedGatewayChainFails() throws {
        let bundle = try Self.bundle(named: "gateway-bundle-tampered")
        let report = ChainVerifier().verify(bundle: bundle)

        #expect(!report.isVerified)
        #expect(report.firstFailure == 1)
        #expect(report.records[0].code == .signatureInvalid)
        #expect(!report.isKeyMismatch, "an edit is not a key problem and must not be reported as one")

        // Everything downstream is untrusted rather than quietly fine.
        for record in report.records.dropFirst() {
            #expect(record.code == .untrusted(dependsOn: 1))
        }
    }
}
