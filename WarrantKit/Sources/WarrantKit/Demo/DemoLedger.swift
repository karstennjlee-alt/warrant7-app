import CryptoKit
import Foundation

/// Builds a genuinely signed, genuinely hash-linked ledger on the device for demo mode.
///
/// §9.2 draws the line precisely: timing may be scripted, truth may not. So these records are
/// really canonicalized, really chained, and really Ed25519 signed — a bundle exported from
/// demo mode verifies through the same ``ChainVerifier`` as a bundle from the gateway, and
/// tampering with it really does fail.
///
/// The key here is a **demo** key, generated on first use and kept in the Keychain. It is not
/// an organization's signing key and it signs nothing that leaves the device. §1 rule 1 is
/// about the org's ledger key, which the phone never sees under any mode.
public struct DemoLedger: Sendable {
    private let signingKey: Curve25519.Signing.PrivateKey
    private let format: ChainFormat

    public init(signingKey: Curve25519.Signing.PrivateKey, format: ChainFormat = .default) {
        self.signingKey = signingKey
        self.format = format
    }

    public var publicKeyBase64: String {
        signingKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// Seal a body into a record: hash it against the previous digest, then sign the hash.
    public func seal(body: JSONValue, previous: Digest256) throws -> (record: JSONValue, digest: Digest256) {
        let canonical = try CanonicalJSON.canonicalBytes(body)
        let digest = Digest256.chained(previous: previous, canonical: canonical, linkage: format.linkage)

        let signedBytes: Data
        switch format.signaturePayload {
        case .digestBytes: signedBytes = digest.bytes
        case .canonicalBody: signedBytes = canonical
        }
        let signature = try signingKey.signature(for: signedBytes)

        guard case .object(var members) = body else { throw Failure.bodyIsNotAnObject }
        members["hash"] = .string(digest.hex)
        members["signature"] = .string(signature.base64EncodedString())
        return (.object(members), digest)
    }

    /// Seal a whole story in order, threading each digest into the next record's `prev`.
    public func sealChain(bodies: [JSONValue]) throws -> [JSONValue] {
        var previous = Digest256.genesis
        var records: [JSONValue] = []
        for body in bodies {
            guard case .object(var members) = body else { throw Failure.bodyIsNotAnObject }
            members["prev"] = .string(previous.hex)
            let sealed = try seal(body: .object(members), previous: previous)
            records.append(sealed.record)
            previous = sealed.digest
        }
        return records
    }

    public enum Failure: Error, Sendable { case bodyIsNotAnObject }
}

/// The three-act story, as receipt bodies. Everything the ledger screen shows comes from here.
public enum DemoStory {
    public static let orgID = "org_demo_northwind"
    public static let orgName = "Contoso Retail"
    public static let approvalID = "wrt_4471"
    public static let recipient = "Northwind"
    public static let agent = "Support Agent 01"
    public static let resource = "payment_882"

    public static func body(
        seq: Int, event: String, actor: String, recipient: String,
        amountMinor: Int, timestamp: Date
    ) -> JSONValue {
        [
            "seq": .int(seq),
            "event": .string(event),
            "actor": .string(actor),
            "resource": .string("refund.create"),
            "recipient": .string(recipient),
            "amount_minor": .int(amountMinor),
            "currency": "USD",
            "ts": .string(WarrantJSON.string(from: timestamp))
        ]
    }

    /// Acts one and two up to the point a human is asked. Act three is the tamper, which
    /// happens to whatever these produce.
    public static func bodies(now: Date) -> [JSONValue] {
        let minute: TimeInterval = 60
        return [
            body(seq: 1, event: "ISSUED", actor: agent, recipient: "J. Alvarez",
                 amountMinor: 12_000, timestamp: now.addingTimeInterval(-58 * minute)),
            body(seq: 2, event: "EXECUTED", actor: "executor", recipient: "J. Alvarez",
                 amountMinor: 12_000, timestamp: now.addingTimeInterval(-58 * minute)),
            body(seq: 3, event: "ISSUED", actor: "Support Agent 02", recipient: "K. Mensah",
                 amountMinor: 890_000, timestamp: now.addingTimeInterval(-40 * minute)),
            body(seq: 4, event: "BLOCKED", actor: "policy", recipient: "K. Mensah",
                 amountMinor: 890_000, timestamp: now.addingTimeInterval(-40 * minute)),
            body(seq: 5, event: "ISSUED", actor: agent, recipient: "P. Novak",
                 amountMinor: 24_000, timestamp: now.addingTimeInterval(-12 * minute)),
            body(seq: 6, event: "EXECUTED", actor: "executor", recipient: "P. Novak",
                 amountMinor: 24_000, timestamp: now.addingTimeInterval(-12 * minute)),
            body(seq: 7, event: "ISSUED", actor: agent, recipient: recipient,
                 amountMinor: 240_000, timestamp: now)
        ]
    }

    public static let activity: [(ActionEvent.Kind, String, String, Int?)] = [
        (.requested, agent, "Read ticket #8842 from a customer reporting a damaged order.", nil),
        (.requested, agent, "Requested a refund of $2,400.00 to Northwind against payment_882.", 240_000),
        (.review, "policy", "Above the $500.00 automatic limit and below the $5,000.00 hard stop. Paused for a human.", 240_000),
        (.requested, "gateway", "Bound the request to one exact digest and sent it to 1 approver device.", nil)
    ]
}
