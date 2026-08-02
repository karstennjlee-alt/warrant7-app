import Foundation

/// Everything the app needs from the outside world, behind one protocol so the demo path and
/// the live path are interchangeable and neither is a special case in the UI (§9.2).
public protocol WarrantDataSource: Sendable {
    func me() async throws -> MeResponse
    func pendingApprovals() async throws -> [Approval]
    func approval(id: String) async throws -> Approval
    func approve(id: String, boundDigest: String, idempotencyKey: String) async throws -> Approval
    func deny(
        id: String, boundDigest: String, idempotencyKey: String,
        reason: DenialReason?, note: String?
    ) async throws -> Approval
    func actions(limit: Int) async throws -> [ActionEvent]
    func receipts(since: Date?) async throws -> [ReceiptRecord]
    func exportBundle() async throws -> EvidenceBundle
    func policy() async throws -> Policy
    func registerDevice(apnsToken: String, environment: String, deviceName: String, orgID: String) async throws
    func resetDemo() async throws
}

/// The live path: everything goes through the gateway, which owns all policy.
public struct LiveDataSource: WarrantDataSource {
    private let client: APIClient
    private let cache: OfflineCache

    public init(client: APIClient, cache: OfflineCache) {
        self.client = client
        self.cache = cache
    }

    public func me() async throws -> MeResponse {
        try await client.send(.me, as: MeResponse.self)
    }

    public func pendingApprovals() async throws -> [Approval] {
        let approvals = try await client.send(.approvals(status: "pending"), as: [Approval].self)
        cache.store(approvals, for: .approvals)
        cache.markSynced()
        return approvals
    }

    public func approval(id: String) async throws -> Approval {
        try await client.send(.approval(id: id), as: Approval.self)
    }

    public func approve(id: String, boundDigest: String, idempotencyKey: String) async throws -> Approval {
        try await client.send(
            .approve(id: id, boundDigest: boundDigest, idempotencyKey: idempotencyKey),
            as: Approval.self
        )
    }

    public func deny(
        id: String, boundDigest: String, idempotencyKey: String,
        reason: DenialReason?, note: String?
    ) async throws -> Approval {
        try await client.send(
            .deny(id: id, boundDigest: boundDigest, idempotencyKey: idempotencyKey, reason: reason, note: note),
            as: Approval.self
        )
    }

    public func actions(limit: Int) async throws -> [ActionEvent] {
        let events = try await client.send(.actions(limit: limit), as: [ActionEvent].self)
        cache.store(events, for: .activity)
        return events
    }

    public func receipts(since: Date?) async throws -> [ReceiptRecord] {
        let data = try await client.send(.receipts(since: since))
        cache.write(data, for: .receipts)
        guard case .array(let raw)? = try? JSONValue.parse(data) else { return [] }
        return raw.compactMap { ReceiptRecord(raw: $0) }
    }

    public func exportBundle() async throws -> EvidenceBundle {
        let data = try await client.send(.receiptsExport)
        cache.write(data, for: .bundle)
        return try EvidenceBundle.parse(data)
    }

    public func policy() async throws -> Policy {
        let policy = try await client.send(.policy, as: Policy.self)
        cache.store(policy, for: .policy)
        return policy
    }

    public func registerDevice(apnsToken: String, environment: String, deviceName: String, orgID: String) async throws {
        _ = try await client.send(.registerDevice(
            apnsToken: apnsToken, environment: environment, deviceName: deviceName, orgID: orgID
        ))
    }

    public func resetDemo() async throws {
        _ = try await client.send(.demoReset)
    }
}
