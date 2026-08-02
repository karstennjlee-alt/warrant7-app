import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

/// One call against the gateway. The whole §4 contract lives here, so a route change is one
/// edit in one file.
public struct Endpoint: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let query: [URLQueryItem]
    public let body: Data?
    /// Present on the two decision routes. The same key on a retry must never execute twice.
    public let idempotencyKey: String?

    public init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        idempotencyKey: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.idempotencyKey = idempotencyKey
    }
}

public extension Endpoint {
    static var me: Endpoint {
        Endpoint(path: "/api/v1/me")
    }

    static func approvals(status: String? = nil) -> Endpoint {
        Endpoint(path: "/api/v1/approvals", query: status.map { [URLQueryItem(name: "status", value: $0)] } ?? [])
    }

    static func approval(id: String) -> Endpoint {
        Endpoint(path: "/api/v1/approvals/\(id)")
    }

    static func approve(id: String, boundDigest: String, idempotencyKey: String) -> Endpoint {
        Endpoint(
            method: .post,
            path: "/api/v1/approvals/\(id)/approve",
            body: try? JSONSerialization.data(withJSONObject: [
                "bound_digest": boundDigest,
                "idempotency_key": idempotencyKey
            ]),
            idempotencyKey: idempotencyKey
        )
    }

    static func deny(
        id: String, boundDigest: String, idempotencyKey: String,
        reason: DenialReason?, note: String?
    ) -> Endpoint {
        var payload: [String: Any] = [
            "bound_digest": boundDigest,
            "idempotency_key": idempotencyKey
        ]
        if let reason { payload["reason"] = reason.rawValue }
        if let note, !note.isEmpty { payload["note"] = note }
        return Endpoint(
            method: .post,
            path: "/api/v1/approvals/\(id)/deny",
            body: try? JSONSerialization.data(withJSONObject: payload),
            idempotencyKey: idempotencyKey
        )
    }

    static func actions(limit: Int = 50) -> Endpoint {
        Endpoint(path: "/api/v1/actions", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    static func receipts(since: Date? = nil) -> Endpoint {
        Endpoint(
            path: "/api/v1/receipts",
            query: since.map { [URLQueryItem(name: "since", value: WarrantJSON.string(from: $0))] } ?? []
        )
    }

    static var receiptsExport: Endpoint {
        Endpoint(path: "/api/v1/receipts/export")
    }

    static var policy: Endpoint {
        Endpoint(path: "/api/v1/policy")
    }

    static func registerDevice(apnsToken: String, environment: String, deviceName: String, orgID: String) -> Endpoint {
        Endpoint(
            method: .post,
            path: "/api/v1/devices",
            body: try? JSONSerialization.data(withJSONObject: [
                "apns_token": apnsToken,
                "environment": environment,
                "device_name": deviceName,
                "org_id": orgID
            ])
        )
    }

    static func deregisterDevice(id: String) -> Endpoint {
        Endpoint(method: .delete, path: "/api/v1/devices/\(id)")
    }

    static var demoReset: Endpoint {
        Endpoint(method: .post, path: "/api/demo/reset")
    }
}
