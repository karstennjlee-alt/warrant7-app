import Foundation

public enum OrgRole: String, Sendable, Codable, Hashable {
    case owner = "OWNER"
    case approver = "APPROVER"
    case viewer = "VIEWER"

    public var label: String {
        switch self {
        case .owner: "OWNER"
        case .approver: "APPROVER"
        case .viewer: "VIEWER"
        }
    }

    public var canDecide: Bool { self == .owner || self == .approver }
    public var canEditPolicy: Bool { self == .owner }

    /// Stated on screen when a control is read-only, so the greying-out is never mysterious.
    public var policyReadOnlyReason: String {
        switch self {
        case .owner: ""
        case .approver: "Approvers can decide requests but not change limits. Ask an owner."
        case .viewer: "Viewers can read the ledger but cannot decide or change limits."
        }
    }
}

public struct Organization: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let role: OrgRole
    /// Controls whether `Reset demo` appears in Settings (§5.7).
    public let isDemo: Bool

    public init(id: String, name: String, role: OrgRole, isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.role = role
        self.isDemo = isDemo
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, role
        case isDemo = "is_demo"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(OrgRole.self, forKey: .role)
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }
}

public struct CurrentUser: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let email: String
    public let displayName: String?

    public init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
    }
}

/// `GET /api/v1/me`
public struct MeResponse: Sendable, Hashable, Codable {
    public let user: CurrentUser
    public let organizations: [Organization]

    public init(user: CurrentUser, organizations: [Organization]) {
        self.user = user
        self.organizations = organizations
    }
}

/// A registered handset. Shown in Settings with a revoke control (§5.7).
public struct RegisteredDevice: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let deviceName: String?
    public let createdAt: Date

    public init(id: String, deviceName: String?, createdAt: Date) {
        self.id = id
        self.deviceName = deviceName
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case createdAt = "created_at"
    }
}
