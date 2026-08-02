import Foundation

/// Owns the two guards that stand between a tap and an irreversible action.
///
/// Both live here rather than in the view so they can be tested without a simulator, and so
/// the Live Activity intent and the card cannot drift into having different rules.
public actor DecisionCoordinator {
    private let source: any WarrantDataSource
    private var inFlight: Set<String> = []
    /// One key per approval, reused across retries. A retry must never execute twice, and a
    /// fresh key on retry is exactly how that happens.
    private var idempotencyKeys: [String: String] = [:]

    public init(source: any WarrantDataSource) {
        self.source = source
    }

    public enum Decision: Sendable {
        case approve
        case deny(reason: DenialReason?, note: String?)
    }

    /// - Returns: the settled approval, or `nil` when a decision for this approval is already
    ///   in flight — the second tap is dropped rather than becoming a second request.
    public func submit(
        _ decision: Decision,
        for approval: Approval,
        now: Date = Date()
    ) async throws -> Approval? {
        // Fail closed. A card whose local countdown has run out must not fire a call that
        // could race into a window the server still thinks is open (§1 rule 4).
        guard approval.isActionable(at: now) else {
            throw WarrantError.locallyExpired
        }
        guard !inFlight.contains(approval.id) else {
            return nil
        }

        inFlight.insert(approval.id)
        defer { inFlight.remove(approval.id) }

        let key = idempotencyKey(for: approval.id)
        switch decision {
        case .approve:
            return try await source.approve(
                id: approval.id, boundDigest: approval.boundDigest, idempotencyKey: key
            )
        case .deny(let reason, let note):
            return try await source.deny(
                id: approval.id, boundDigest: approval.boundDigest, idempotencyKey: key,
                reason: reason, note: note
            )
        }
    }

    public func idempotencyKey(for approvalID: String) -> String {
        if let existing = idempotencyKeys[approvalID] { return existing }
        let key = "\(approvalID)-\(UUID().uuidString)"
        idempotencyKeys[approvalID] = key
        return key
    }

    public func isInFlight(_ approvalID: String) -> Bool {
        inFlight.contains(approvalID)
    }

    /// After a reset, a fresh decision on the same approval id is a genuinely new decision.
    public func forget(_ approvalID: String) {
        idempotencyKeys[approvalID] = nil
        inFlight.remove(approvalID)
    }
}
