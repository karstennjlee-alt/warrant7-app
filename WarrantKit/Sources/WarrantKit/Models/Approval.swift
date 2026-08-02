import Foundation

/// Where an approval ended up. The four terminal cases each get their own full card (§5.1),
/// because "what happened" is the only thing the person actually wants to know.
public enum ApprovalStatus: String, Sendable, Codable, Hashable {
    case pending = "PENDING"
    case approvedExecuted = "APPROVED_EXECUTED"
    case denied = "DENIED"
    case expired = "EXPIRED"
    case alreadyDecided = "ALREADY_DECIDED"
    case executionFailed = "EXECUTION_FAILED"

    public var isTerminal: Bool { self != .pending }

    /// Mono, uppercase, as every system-computed string in this product is.
    public var label: String {
        switch self {
        case .pending: "PENDING"
        case .approvedExecuted: "APPROVED AND EXECUTED"
        case .denied: "DENIED"
        case .expired: "EXPIRED"
        case .alreadyDecided: "ALREADY DECIDED"
        case .executionFailed: "EXECUTION FAILED"
        }
    }
}

/// One decision request, rendered on the card that is the entire point of the app.
///
/// The device decides nothing here. It renders what the gateway computed and transmits what a
/// human answered.
public struct Approval: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let orgID: String

    /// The one plain sentence, largest thing on screen: "Refund $2,400.00 to Northwind".
    /// Composed by the gateway so the phone and the console cannot drift apart.
    public let actionLine: String
    public let amount: Money

    public let requestedBy: String
    public let resource: String
    public let impact: String
    public let reversibility: String
    /// "Your rule caps automatic refunds at $500."
    public let whyReviewing: String

    /// The exact action this approval binds to. Approving binds to this and nothing broader.
    public let boundDigest: String

    /// What the agent said it was doing, in its own words. Shown verbatim so a person can
    /// judge the reasoning rather than a summary of it.
    public let agentStatement: String?
    /// The source text the agent read — a support ticket, an email, a form. Untrusted by
    /// definition, and shown as such.
    public let sourceText: String?
    /// The span of `sourceText` that is an instruction wearing a system voice. Highlighted so
    /// a prompt injection is visible to a human eye rather than only to a filter.
    public let sourceInjection: String?
    public let reference: String?

    public let createdAt: Date
    public let expiresAt: Date

    public var status: ApprovalStatus
    public var decidedAt: Date?
    public var decidedBy: String?
    public var denialReason: String?
    /// The ledger sequence this decision produced, so a terminal card can link into evidence.
    public var receiptSequence: Int?

    public init(
        id: String, orgID: String, actionLine: String, amount: Money, requestedBy: String,
        resource: String, impact: String, reversibility: String, whyReviewing: String,
        boundDigest: String, createdAt: Date, expiresAt: Date, status: ApprovalStatus,
        agentStatement: String? = nil, sourceText: String? = nil, sourceInjection: String? = nil,
        reference: String? = nil,
        decidedAt: Date? = nil, decidedBy: String? = nil, denialReason: String? = nil,
        receiptSequence: Int? = nil
    ) {
        self.id = id
        self.orgID = orgID
        self.actionLine = actionLine
        self.amount = amount
        self.requestedBy = requestedBy
        self.resource = resource
        self.impact = impact
        self.reversibility = reversibility
        self.whyReviewing = whyReviewing
        self.boundDigest = boundDigest
        self.agentStatement = agentStatement
        self.sourceText = sourceText
        self.sourceInjection = sourceInjection
        self.reference = reference
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.decidedAt = decidedAt
        self.decidedBy = decidedBy
        self.denialReason = denialReason
        self.receiptSequence = receiptSequence
    }

    // MARK: - Expiry

    /// T-09: actionable at `expiresAt - 1s`, not actionable at `expiresAt`.
    ///
    /// Fail closed. The boundary belongs to expiry, not to the approver — a request that is
    /// exactly at its deadline is over.
    public func isActionable(at now: Date = Date()) -> Bool {
        status == .pending && now < expiresAt
    }

    public func secondsRemaining(at now: Date = Date()) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }

    /// The digest, head and tail, for a card that has to stay readable on a phone.
    /// Tapping reveals ``boundDigest`` in full (§1 rule 3).
    public var boundDigestShort: String {
        let hex = boundDigest.replacingOccurrences(of: "sha256:", with: "")
        guard hex.count > 20 else { return boundDigest }
        return "sha256:\(hex.prefix(4))…\(hex.suffix(4))"
    }

    /// The recipient, pulled off the action line for the places that need it alone.
    public var recipient: String {
        actionLine.components(separatedBy: " to ").last ?? actionLine
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case orgID = "org_id"
        case actionLine = "action_line"
        case amountMinor = "amount_minor"
        case currency
        case requestedBy = "requested_by"
        case resource
        case impact
        case reversibility
        case whyReviewing = "why_reviewing"
        case boundDigest = "bound_digest"
        case agentStatement = "agent_statement"
        case sourceText = "source_text"
        case sourceInjection = "source_injection"
        case reference
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case status
        case decidedAt = "decided_at"
        case decidedBy = "decided_by"
        case denialReason = "denial_reason"
        case receiptSequence = "receipt_sequence"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        orgID = try c.decode(String.self, forKey: .orgID)
        actionLine = try c.decode(String.self, forKey: .actionLine)
        amount = Money(
            minorUnits: try c.decode(Int.self, forKey: .amountMinor),
            currencyCode: try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        )
        requestedBy = try c.decode(String.self, forKey: .requestedBy)
        resource = try c.decode(String.self, forKey: .resource)
        impact = try c.decode(String.self, forKey: .impact)
        reversibility = try c.decode(String.self, forKey: .reversibility)
        whyReviewing = try c.decode(String.self, forKey: .whyReviewing)
        boundDigest = try c.decode(String.self, forKey: .boundDigest)
        agentStatement = try c.decodeIfPresent(String.self, forKey: .agentStatement)
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText)
        sourceInjection = try c.decodeIfPresent(String.self, forKey: .sourceInjection)
        reference = try c.decodeIfPresent(String.self, forKey: .reference)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        status = try c.decode(ApprovalStatus.self, forKey: .status)
        decidedAt = try c.decodeIfPresent(Date.self, forKey: .decidedAt)
        decidedBy = try c.decodeIfPresent(String.self, forKey: .decidedBy)
        denialReason = try c.decodeIfPresent(String.self, forKey: .denialReason)
        receiptSequence = try c.decodeIfPresent(Int.self, forKey: .receiptSequence)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(orgID, forKey: .orgID)
        try c.encode(actionLine, forKey: .actionLine)
        try c.encode(amount.minorUnits, forKey: .amountMinor)
        try c.encode(amount.currencyCode, forKey: .currency)
        try c.encode(requestedBy, forKey: .requestedBy)
        try c.encode(resource, forKey: .resource)
        try c.encode(impact, forKey: .impact)
        try c.encode(reversibility, forKey: .reversibility)
        try c.encode(whyReviewing, forKey: .whyReviewing)
        try c.encode(boundDigest, forKey: .boundDigest)
        try c.encodeIfPresent(agentStatement, forKey: .agentStatement)
        try c.encodeIfPresent(sourceText, forKey: .sourceText)
        try c.encodeIfPresent(sourceInjection, forKey: .sourceInjection)
        try c.encodeIfPresent(reference, forKey: .reference)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(decidedAt, forKey: .decidedAt)
        try c.encodeIfPresent(decidedBy, forKey: .decidedBy)
        try c.encodeIfPresent(denialReason, forKey: .denialReason)
        try c.encodeIfPresent(receiptSequence, forKey: .receiptSequence)
    }
}

/// Why a person refused. Goes into the receipt and back to the agent, so it is structured
/// rather than free text alone.
public enum DenialReason: String, Sendable, Codable, CaseIterable, Hashable {
    case promptInjection = "PROMPT_INJECTION"
    case exceedsOrderValue = "EXCEEDS_ORDER_VALUE"
    case needsSupervisor = "NEEDS_SUPERVISOR"
    case notValid = "NOT_VALID"

    public var label: String {
        switch self {
        case .promptInjection: "Prompt injection in the request"
        case .exceedsOrderValue: "Amount exceeds the order value"
        case .needsSupervisor: "Needs a supervisor, not me"
        case .notValid: "Not a valid case"
        }
    }
}
