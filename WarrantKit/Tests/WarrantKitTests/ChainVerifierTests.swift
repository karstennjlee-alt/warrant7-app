import Testing
import CryptoKit
import Foundation
@testable import WarrantKit

@Suite("Offline chain verification")
struct ChainVerifierTests {

    /// Stands in for the gateway's signer. The device under test never sees this key — only
    /// `signingKey.publicKey` crosses into the verifier.
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let verifier = ChainVerifier()

    /// Build a signed, hash-linked chain the way the gateway is specified to: digest over the
    /// canonical body including `prev`, signature over the raw digest bytes.
    private func makeChain(amounts: [Int]) throws -> [JSONValue] {
        var previous = Digest256.genesis
        var records: [JSONValue] = []

        for (index, amount) in amounts.enumerated() {
            let body: JSONValue = [
                "actor": "support-agent-01",
                "amount_minor": .int(amount),
                "currency": "USD",
                "event": "ISSUE",
                "prev": .string(previous.hex),
                "recipient": "dana.reyes",
                "resource": "refund.create",
                "seq": .int(index + 1),
                "ts": "2026-08-02T14:22:07Z"
            ]
            let digest = try Digest256.of(body)
            let signature = try signingKey.signature(for: digest.bytes)

            guard case .object(var members) = body else { throw TestFailure.notAnObject }
            members["digest"] = .string(digest.hex)
            members["signature"] = .string(signature.base64EncodedString())
            records.append(.object(members))
            previous = digest
        }
        return records
    }

    enum TestFailure: Error { case notAnObject }

    @Test("An untouched chain verifies")
    func intactChainVerifies() throws {
        let chain = try makeChain(amounts: [120_00, 12_000, 240_000])
        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(result.isVerified)
        #expect(result.records.count == 3)
        #expect(result.records.filter { !$0.verdict.isOK }.isEmpty)
    }

    /// The tamper lab, as a test: edit one stored amount and the recomputed digest stops
    /// matching the signed one.
    @Test("Editing an amount fails the record that changed")
    func tamperedAmountFailsVerification() throws {
        var chain = try makeChain(amounts: [120_00, 12_000, 240_000])
        guard case .object(var members) = chain[2] else { throw TestFailure.notAnObject }
        members["amount_minor"] = .int(24_000_000)
        chain[2] = .object(members)

        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(!result.isVerified)
        #expect(result.firstFailureIndex == 2)
        #expect(result.records[0].verdict.isOK)
        #expect(result.records[1].verdict.isOK)
        guard case .digestMismatch = result.records[2].verdict else {
            Issue.record("expected a digest mismatch, got \(result.records[2].verdict)")
            return
        }
    }

    @Test("Everything after the first break is untrusted, not merely unchecked")
    func recordsAfterABreakAreUntrusted() throws {
        var chain = try makeChain(amounts: [120_00, 12_000, 240_000, 500_00])
        guard case .object(var members) = chain[1] else { throw TestFailure.notAnObject }
        members["recipient"] = "someone.else"
        chain[1] = .object(members)

        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(result.firstFailureIndex == 1)
        #expect(result.records[2].verdict == .untrusted)
        #expect(result.records[3].verdict == .untrusted)
    }

    @Test("Re-signing a forged record with the wrong key still fails")
    func forgedSignatureFails() throws {
        var chain = try makeChain(amounts: [240_000])
        let attackerKey = Curve25519.Signing.PrivateKey()

        guard case .object(var members) = chain[0] else { throw TestFailure.notAnObject }
        members["amount_minor"] = .int(24_000_000)
        let body = JSONValue.object(members).removingKeys(["digest", "signature"])
        let digest = try Digest256.of(body)
        members["digest"] = .string(digest.hex)
        members["signature"] = .string(try attackerKey.signature(for: digest.bytes).base64EncodedString())
        chain[0] = .object(members)

        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(!result.isVerified)
        #expect(result.records[0].verdict == .badSignature)
    }

    @Test("Removing a record breaks the link that named it")
    func deletingARecordBreaksTheChain() throws {
        var chain = try makeChain(amounts: [120_00, 12_000, 240_000])
        chain.remove(at: 1)

        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(result.firstFailureIndex == 1)
        guard case .brokenLink = result.records[1].verdict else {
            Issue.record("expected a broken link, got \(result.records[1].verdict)")
            return
        }
    }

    @Test("A missing envelope field is malformed, never a pass")
    func missingSignatureIsMalformed() throws {
        var chain = try makeChain(amounts: [240_000])
        chain[0] = chain[0].removingKeys(["signature"])

        let result = verifier.verify(records: chain, publicKey: signingKey.publicKey)

        #expect(result.records[0].verdict == .malformed("signature"))
    }
}

@Suite("Digest and money")
struct SupportingTypeTests {

    @Test("Genesis is 64 zeros")
    func genesisDigest() {
        #expect(Digest256.genesis.hex == String(repeating: "0", count: 64))
    }

    @Test("Hex round trips")
    func hexRoundTrip() throws {
        let digest = Digest256.of(Data("warrant".utf8))
        #expect(Digest256(hex: digest.hex) == digest)
        #expect(Digest256(hex: "not hex") == nil)
        #expect(Digest256(hex: "ab") == nil)
    }

    @Test("Known SHA-256 vector")
    func knownVector() {
        #expect(Digest256.of(Data("abc".utf8)).hex
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Money stays in minor units until the view boundary")
    func moneyFormatting() {
        let amount = Money(minorUnits: 240_000)
        #expect(amount.minorUnits == 240_000)
        #expect(amount.formatted(locale: Locale(identifier: "en_US")) == "$2,400.00")
    }
}
