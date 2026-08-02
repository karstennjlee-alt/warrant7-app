import Foundation

public enum PolicyOutcome: String, Sendable, Hashable {
    case allow = "ALLOW"
    case review = "REVIEW"
    case block = "BLOCK"
}

/// The active rule, as the gateway reports it.
///
/// Editing creates a new version. Old versions are never mutated — that is the whole point of
/// a version history in a product about evidence.
public struct Policy: Sendable, Hashable, Codable {
    public let version: Int
    public let resource: String
    public let autoLimit: Money
    public let blockLimit: Money
    public let expirySeconds: Int
    /// Plain language, composed server-side: "Automatically allow refunds up to $500…"
    public let readableRule: String
    public let updatedAt: Date

    public init(
        version: Int, resource: String, autoLimit: Money, blockLimit: Money,
        expirySeconds: Int, readableRule: String, updatedAt: Date
    ) {
        self.version = version
        self.resource = resource
        self.autoLimit = autoLimit
        self.blockLimit = blockLimit
        self.expirySeconds = expirySeconds
        self.readableRule = readableRule
        self.updatedAt = updatedAt
    }

    /// **Illustration only.** Drives the tester slider in §5.6 so a person can see where an
    /// amount lands. It never decides anything: no request is allowed, paused, or blocked by
    /// this function, and no call site may treat its result as authoritative. The gateway
    /// owns policy, and the device duplicating that logic is exactly what §4 forbids.
    public func preview(for amount: Money) -> PolicyOutcome {
        if amount.minorUnits <= autoLimit.minorUnits { return .allow }
        if amount.minorUnits <= blockLimit.minorUnits { return .review }
        return .block
    }

    private enum CodingKeys: String, CodingKey {
        case version, resource, currency
        case autoLimitMinor = "auto_limit_minor"
        case blockLimitMinor = "block_limit_minor"
        case expirySeconds = "expiry_seconds"
        case readableRule = "readable_rule"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        version = try c.decode(Int.self, forKey: .version)
        resource = try c.decode(String.self, forKey: .resource)
        autoLimit = Money(minorUnits: try c.decode(Int.self, forKey: .autoLimitMinor), currencyCode: currency)
        blockLimit = Money(minorUnits: try c.decode(Int.self, forKey: .blockLimitMinor), currencyCode: currency)
        expirySeconds = try c.decode(Int.self, forKey: .expirySeconds)
        readableRule = try c.decode(String.self, forKey: .readableRule)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(resource, forKey: .resource)
        try c.encode(autoLimit.currencyCode, forKey: .currency)
        try c.encode(autoLimit.minorUnits, forKey: .autoLimitMinor)
        try c.encode(blockLimit.minorUnits, forKey: .blockLimitMinor)
        try c.encode(expirySeconds, forKey: .expirySeconds)
        try c.encode(readableRule, forKey: .readableRule)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// What the agent did, step by step (§5.3). Plain sentences only.
///
/// Nothing in here may carry hidden model reasoning or a credential, in any state including
/// errors — the feed is read by people who are deciding whether to trust the system.
public struct ActionEvent: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case requested = "REQUESTED"
        case allowed = "ALLOWED"
        case review = "REVIEW"
        case blocked = "BLOCKED"
        case executed = "EXECUTED"
        case denied = "DENIED"
        case expired = "EXPIRED"
        case failed = "FAILED"
    }

    public let id: String
    public let requestID: String
    public let kind: Kind
    public let line: String
    public let timestamp: Date
    public let actor: String
    public let amount: Money?

    public init(
        id: String, requestID: String, kind: Kind, line: String,
        timestamp: Date, actor: String, amount: Money? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.kind = kind
        self.line = line
        self.timestamp = timestamp
        self.actor = actor
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, line, actor, currency
        case requestID = "request_id"
        case timestamp = "ts"
        case amountMinor = "amount_minor"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        requestID = try c.decode(String.self, forKey: .requestID)
        kind = try c.decode(Kind.self, forKey: .kind)
        line = try c.decode(String.self, forKey: .line)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        actor = try c.decode(String.self, forKey: .actor)
        if let minor = try c.decodeIfPresent(Int.self, forKey: .amountMinor) {
            amount = Money(minorUnits: minor, currencyCode: try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD")
        } else {
            amount = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(kind, forKey: .kind)
        try c.encode(line, forKey: .line)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(actor, forKey: .actor)
        try c.encodeIfPresent(amount?.minorUnits, forKey: .amountMinor)
        try c.encodeIfPresent(amount?.currencyCode, forKey: .currency)
    }
}

/// The hall pass, as shown when an activity group is expanded (§5.3).
public struct HallPass: Sendable, Hashable {
    public let passNumber: String
    public let bearer: String
    public let permitted: String
    public let destination: String
    public let amount: Money
    public let validUntil: Date
    public let binding: String

    public init(
        passNumber: String, bearer: String, permitted: String, destination: String,
        amount: Money, validUntil: Date, binding: String
    ) {
        self.passNumber = passNumber
        self.bearer = bearer
        self.permitted = permitted
        self.destination = destination
        self.amount = amount
        self.validUntil = validUntil
        self.binding = binding
    }
}
