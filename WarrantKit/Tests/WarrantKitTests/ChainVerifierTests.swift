import Testing
import CryptoKit
import Foundation
@testable import WarrantKit

/// T-02 through T-08. Each failure mode must be told apart from the others — a person looking
/// at a red record needs to know whether their evidence was altered, reordered, thinned out,
/// or simply checked against the wrong key.
@Suite("T-02…T-08 · Chain verification")
struct ChainVerifierTests {

    let signingKey = Curve25519.Signing.PrivateKey()
    let verifier = ChainVerifier()

    /// Stands in for the gateway's signer. The device under test only ever sees the public half.
    func makeRecords(amounts: [Int]) throws -> [JSONValue] {
        let ledger = DemoLedger(signingKey: signingKey)
        let bodies = amounts.enumerated().map { index, amount in
            DemoStory.body(
                seq: index + 1, event: "ISSUED", actor: "Support Agent 01",
                recipient: "Northwind", amountMinor: amount,
                timestamp: Date(timeIntervalSince1970: 1_785_000_000 + Double(index))
            )
        }
        return try ledger.sealChain(bodies: bodies)
    }

    func bundle(_ records: [JSONValue], key: Curve25519.Signing.PublicKey? = nil) -> EvidenceBundle {
        EvidenceBundle(
            organization: "Contoso Retail",
            exportedAt: nil,
            publicKeyBase64: (key ?? signingKey.publicKey).rawRepresentation.base64EncodedString(),
            records: records
        )
    }

    // MARK: - T-02

    @Test("T-02 · A valid chain verifies end to end")
    func validChain() throws {
        let report = verifier.verify(bundle: bundle(try makeRecords(amounts: [12_000, 24_000, 240_000])))

        #expect(report.isVerified)
        #expect(report.records.count == 3)
        #expect(report.records.filter { !$0.isOK }.isEmpty)
        #expect(report.summary == "3 records verified.")
    }

    // MARK: - T-03

    @Test("T-03 · An altered amount fails at that exact index, with SIGNATURE_INVALID")
    func alteredAmount() throws {
        var records = try makeRecords(amounts: [12_000, 24_000, 240_000])
        guard case .object(var members) = records[1] else { throw TestFailure.notAnObject }
        members["amount_minor"] = .int(24_000_000)
        records[1] = .object(members)

        let report = verifier.verify(bundle: bundle(records))

        #expect(!report.isVerified)
        #expect(report.firstFailure == 2)
        #expect(report.records[0].code == .ok)
        #expect(report.records[1].code == .signatureInvalid)
        #expect(report.records[1].code.label == "SIGNATURE_INVALID")
        #expect(!report.isKeyMismatch, "an edit is not a key problem and must not be reported as one")
    }

    // MARK: - T-04

    @Test("T-04 · A deleted record is a SEQUENCE_GAP, not a signature problem")
    func deletedRecord() throws {
        var records = try makeRecords(amounts: [12_000, 24_000, 240_000, 50_000])
        records.remove(at: 1)

        let report = verifier.verify(bundle: bundle(records))

        #expect(!report.isVerified)
        #expect(report.records[1].code == .sequenceGap)
        #expect(report.records[1].code.label == "SEQUENCE_GAP")
        #expect(report.records[1].code.message != VerificationCode.signatureInvalid.message,
                "T-04 must read differently from T-03")
    }

    // MARK: - T-05

    @Test("T-05 · Reordered records are CHAIN_BROKEN, distinct from T-03 and T-04")
    func reorderedRecords() throws {
        var records = try makeRecords(amounts: [12_000, 24_000, 240_000, 50_000])
        records.swapAt(1, 2)

        let report = verifier.verify(bundle: bundle(records))

        #expect(!report.isVerified)
        #expect(report.records[1].code == .chainBroken)
        let messages = Set([
            VerificationCode.chainBroken.message,
            VerificationCode.sequenceGap.message,
            VerificationCode.signatureInvalid.message
        ])
        #expect(messages.count == 3, "the three failure modes must not share wording")
    }

    // MARK: - T-06

    @Test("T-06 · A forged signature is caught and the record is named")
    func forgedSignature() throws {
        var records = try makeRecords(amounts: [240_000, 12_000])
        let attacker = Curve25519.Signing.PrivateKey()

        // Re-sign a doctored record with a key that is not the org's, and repair the stored
        // hash so only the signature betrays it.
        guard case .object(var members) = records[0] else { throw TestFailure.notAnObject }
        members["amount_minor"] = .int(1)
        let body = JSONValue.object(members).removingKeys(ReceiptRecord.envelopeKeys)
        let canonical = try CanonicalJSON.canonicalBytes(body)
        let digest = Digest256.chained(previous: .genesis, canonical: canonical)
        members["hash"] = .string(digest.hex)
        members["signature"] = .string(try attacker.signature(for: digest.bytes).base64EncodedString())
        records[0] = .object(members)

        let report = verifier.verify(bundle: bundle(records))

        #expect(!report.isVerified)
        #expect(report.firstFailure == 1)
        #expect(report.records[0].code == .signatureInvalid)
    }

    // MARK: - T-07

    @Test("T-07 · Everything downstream of a failure is UNTRUSTED_DEPENDS_ON_n")
    func downstreamUntrusted() throws {
        var records = try makeRecords(amounts: [12_000, 24_000, 240_000, 50_000, 9_900])
        guard case .object(var members) = records[1] else { throw TestFailure.notAnObject }
        members["recipient"] = "somebody.else"
        records[1] = .object(members)

        let report = verifier.verify(bundle: bundle(records))

        #expect(report.firstFailure == 2)
        for index in 2..<records.count {
            #expect(report.records[index].code == .untrusted(dependsOn: 2))
            #expect(report.records[index].code.label == "UNTRUSTED_DEPENDS_ON_2")
        }
    }

    // MARK: - T-08

    @Test("T-08 · The wrong public key says so, rather than crying tampering")
    func wrongPublicKey() throws {
        let records = try makeRecords(amounts: [12_000, 24_000, 240_000])
        let unrelated = Curve25519.Signing.PrivateKey().publicKey

        let report = verifier.verify(bundle: bundle(records, key: unrelated))

        #expect(!report.isVerified)
        #expect(report.isKeyMismatch)
        #expect(report.records.allSatisfy { $0.code == .keyMismatch })
        #expect(report.summary == "Nothing verified under this key.")
        // The distinction that matters: intact evidence checked against the wrong key is not
        // evidence of tampering, and saying so would be a false accusation.
        #expect(VerificationCode.keyMismatch.message.contains("not proof the records were altered"))
    }

    // MARK: - Demo mode is really signed

    @Test("A bundle produced by demo mode really verifies")
    func demoBundleVerifies() async throws {
        let source = DemoDataSource(keychain: KeychainStore(service: "test.\(UUID().uuidString)"))
        let report = verifier.verify(bundle: try await source.exportBundle())
        #expect(report.isVerified, "demo outcomes are scripted in timing only, never in truth")
    }

    @Test("Tampering with a demo bundle really fails")
    func demoTamperFails() async throws {
        let source = DemoDataSource(keychain: KeychainStore(service: "test.\(UUID().uuidString)"))
        let report = verifier.verify(bundle: await source.tamperedBundle())

        #expect(!report.isVerified)
        #expect(report.firstFailure == 7)
    }

    enum TestFailure: Error { case notAnObject }
}
