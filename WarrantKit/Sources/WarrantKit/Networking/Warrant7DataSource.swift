import Foundation

/// Speaks warrant7's dialect of the same idea.
///
/// warrant7 is a separate deployment by a separate author. It implements the same product but
/// names almost everything differently — `approval_id` not `id`, `action` not `action_line`,
/// `why_interrupted` not `why_reviewing`, `automatic_limit_minor` not `auto_limit_minor` — and
/// wraps its collections in an envelope rather than returning bare arrays.
///
/// Rather than bend the app's model to one server's vocabulary, the translation lives here. The
/// rest of the app cannot tell which backend it is talking to, which is the point: the same
/// approval card renders whichever gateway is configured.
///
/// Three routes the app expects do not exist there: `/me`, `/devices`, `/actions`. Each is
/// handled explicitly below rather than left to fail as a mystery.
public struct Warrant7DataSource: WarrantDataSource {
    private let client: APIClient
    private let cache: OfflineCache
    private let email: String

    public init(client: APIClient, cache: OfflineCache, email: String) {
        self.client = client
        self.cache = cache
        self.email = email
    }

    // MARK: - Identity

    /// `/api/v1/me` returns 404 there. `/approvers/join` is the substitute: it is idempotent,
    /// it returns the organization and the caller's role, and it is required anyway.
    ///
    /// warrant7's row-level security is membership-driven, so a user who has just signed in can
    /// read nothing until this call creates their membership. Skipping it produces a 403 that
    /// looks exactly like an empty queue.
    public func me() async throws -> MeResponse {
        let data = try await client.send(Endpoint(method: .post, path: "/api/v1/approvers/join", body: Data("{}".utf8)))
        guard let root = try? JSONValue.parse(data) else { throw WarrantError.decoding }

        let org = root["organization"]
        let role = root["membership"]?["role"]?.stringValue ?? "approver"

        return MeResponse(
            user: CurrentUser(
                id: root["membership"]?["user_id"]?.stringValue ?? "—",
                email: email,
                displayName: email.components(separatedBy: "@").first
            ),
            organizations: [Organization(
                id: org?["id"]?.stringValue ?? "warrant7",
                name: org?["name"]?.stringValue ?? "Warrant7",
                role: OrgRole(rawValue: role.uppercased()) ?? .approver,
                isDemo: org?["slug"]?.stringValue?.contains("demo") ?? false
            )]
        )
    }

    // MARK: - Approvals

    public func pendingApprovals() async throws -> [Approval] {
        let data = try await client.send(Endpoint(path: "/api/v1/approvals"))
        guard case .array(let raw)? = try? JSONValue.parse(data)["approvals"] else { return [] }
        let approvals = raw.compactMap(Self.approval(from:))
        cache.store(approvals, for: .approvals)
        cache.markSynced()
        return approvals
    }

    public func approval(id: String) async throws -> Approval {
        let data = try await client.send(Endpoint(path: "/api/v1/approvals/\(id)"))
        guard let root = try? JSONValue.parse(data), let approval = Self.approval(from: root) else {
            throw WarrantError.notFound
        }
        return approval
    }

    public func approve(id: String, boundDigest: String, idempotencyKey: String) async throws -> Approval {
        try await decide(id: id, action: "approve", payload: [:], idempotencyKey: idempotencyKey)
    }

    public func deny(
        id: String, boundDigest: String, idempotencyKey: String,
        reason: DenialReason?, note: String?
    ) async throws -> Approval {
        var payload: [String: Any] = [:]
        if let reason { payload["reason"] = reason.label }
        if let note, !note.isEmpty { payload["note"] = note }
        return try await decide(id: id, action: "deny", payload: payload, idempotencyKey: idempotencyKey)
    }

    private func decide(
        id: String, action: String, payload: [String: Any], idempotencyKey: String
    ) async throws -> Approval {
        let data = try await client.send(Endpoint(
            method: .post,
            path: "/api/v1/approvals/\(id)/\(action)",
            body: try? JSONSerialization.data(withJSONObject: payload),
            idempotencyKey: idempotencyKey
        ))

        // The decision response is not the approval object; re-read so the card shows what the
        // server now believes rather than what we hoped it would.
        if let refreshed = try? await approval(id: id) { return refreshed }

        guard let root = try? JSONValue.parse(data), let approval = Self.approval(from: root) else {
            throw WarrantError.decoding
        }
        return approval
    }

    // MARK: - Translation

    static func approval(from raw: JSONValue) -> Approval? {
        guard let id = raw["approval_id"]?.stringValue ?? raw["id"]?.stringValue,
              let action = raw["action"]?.stringValue ?? raw["action_line"]?.stringValue,
              let expiresText = raw["expires_at"]?.stringValue,
              let expiresAt = WarrantJSON.date(from: expiresText) else { return nil }

        let minor = Int(raw["amount_minor"]?.numberValue ?? 0)
        let currency = raw["currency"]?.stringValue ?? "USD"
        let decision = (raw["decision"]?.stringValue ?? "PENDING").uppercased()

        // `created_at` is not sent. Deriving it from the remaining seconds keeps the countdown
        // ring proportional instead of starting it half-drained.
        let remaining = raw["expires_in_seconds"]?.numberValue ?? 120
        let createdAt = WarrantJSON.date(from: raw["created_at"]?.stringValue ?? "")
            ?? expiresAt.addingTimeInterval(-max(remaining, 120))

        let digest = raw["digest"]?.stringValue ?? ""

        return Approval(
            id: id,
            orgID: raw["org_id"]?.stringValue ?? "warrant7",
            actionLine: action,
            amount: Money(minorUnits: minor, currencyCode: currency),
            requestedBy: raw["requested_by"]?.stringValue ?? "—",
            resource: raw["resource_id"]?.stringValue ?? raw["resource"]?.stringValue ?? "—",
            impact: raw["impact"]?.stringValue ?? "—",
            reversibility: raw["reversibility"]?.stringValue ?? "—",
            whyReviewing: raw["why_interrupted"]?.stringValue ?? raw["why_reviewing"]?.stringValue ?? "—",
            boundDigest: digest.isEmpty ? "—" : (digest.hasPrefix("sha256:") ? digest : "sha256:\(digest)"),
            createdAt: createdAt,
            expiresAt: expiresAt,
            status: status(from: decision),
            agentStatement: raw["agent_statement"]?.stringValue ?? raw["agent_reasoning"]?.stringValue,
            sourceText: raw["ticket_body"]?.stringValue ?? raw["source_text"]?.stringValue,
            sourceInjection: raw["injection"]?.stringValue ?? raw["source_injection"]?.stringValue,
            reference: raw["ticket_reference"]?.stringValue ?? raw["reference"]?.stringValue,
            decidedAt: WarrantJSON.date(from: raw["decided_at"]?.stringValue ?? ""),
            decidedBy: raw["decided_by"]?.stringValue,
            denialReason: raw["reason"]?.stringValue ?? raw["denial_reason"]?.stringValue,
            receiptSequence: raw["receipt_sequence"]?.numberValue.map { Int($0) }
        )
    }

    static func status(from decision: String) -> ApprovalStatus {
        switch decision {
        case "PENDING": .pending
        case "APPROVED", "APPROVED_EXECUTED", "HUMAN_APPROVED": .approvedExecuted
        case "DENIED", "HUMAN_DENIED": .denied
        case "EXPIRED": .expired
        case "ALREADY_CONSUMED", "ALREADY_DECIDED": .alreadyDecided
        default: .executionFailed
        }
    }

    // MARK: - Policy, receipts, evidence

    public func policy() async throws -> Policy {
        let data = try await client.send(Endpoint(path: "/api/v1/policy"))
        guard let root = try? JSONValue.parse(data) else { throw WarrantError.decoding }
        let current = root["current"] ?? root

        let currency = current["currency"]?.stringValue ?? "USD"
        let policy = Policy(
            version: Int(current["version"]?.numberValue ?? 1),
            resource: current["action"]?.stringValue ?? "issue_refund",
            autoLimit: Money(minorUnits: Int(current["automatic_limit_minor"]?.numberValue ?? 50_000), currencyCode: currency),
            blockLimit: Money(minorUnits: Int(current["review_limit_minor"]?.numberValue ?? 500_000), currencyCode: currency),
            expirySeconds: Int(current["approval_ttl_seconds"]?.numberValue ?? 120),
            readableRule: current["readable_rule"]?.stringValue ?? root["readable_rule"]?.stringValue ?? "",
            updatedAt: WarrantJSON.date(from: current["created_at"]?.stringValue ?? "") ?? Date()
        )
        cache.store(policy, for: .policy)
        return policy
    }

    public func receipts(since: Date?) async throws -> [ReceiptRecord] {
        let data = try await client.send(Endpoint(path: "/api/v1/receipts"))
        cache.write(data, for: .receipts)
        guard case .array(let raw)? = try? JSONValue.parse(data)["receipts"] else { return [] }
        return raw.compactMap { ReceiptRecord(raw: $0, format: .warrant7) }
    }

    public func exportBundle() async throws -> EvidenceBundle {
        let data = try await client.send(Endpoint(path: "/api/v1/evidence/export"))
        cache.write(data, for: .bundle)
        return try EvidenceBundle.parse(data)
    }

    // MARK: - Absent there

    /// No activity feed exists. An empty list is honest; inventing one from receipts would put
    /// words in an agent's mouth.
    public func actions(limit: Int) async throws -> [ActionEvent] { [] }

    /// No device registry. Push is not wired to this backend, and pretending to register would
    /// make a silent notification failure look like a delivery problem.
    public func registerDevice(apnsToken: String, environment: String, deviceName: String, orgID: String) async throws {}

    public func resetDemo() async throws {}
}
