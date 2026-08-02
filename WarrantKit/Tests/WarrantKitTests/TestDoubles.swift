import Foundation
@testable import WarrantKit

/// A data source that records what it was asked to do, so tests can assert on the number of
/// calls rather than on their effects.
actor RecordingDataSource: WarrantDataSource {
    private(set) var approveCalls: [(id: String, digest: String, key: String)] = []
    private(set) var denyCalls: [(id: String, key: String)] = []
    /// Makes a decision take long enough for a second tap to land while the first is in flight.
    var decisionDelay: Duration = .zero
    var approval: Approval

    init(approval: Approval) {
        self.approval = approval
    }

    func setDecisionDelay(_ delay: Duration) { decisionDelay = delay }

    func me() async throws -> MeResponse {
        MeResponse(user: CurrentUser(id: "u", email: "e@example.com"), organizations: [])
    }
    func pendingApprovals() async throws -> [Approval] { [approval] }
    func approval(id: String) async throws -> Approval { approval }

    func approve(id: String, boundDigest: String, idempotencyKey: String) async throws -> Approval {
        approveCalls.append((id, boundDigest, idempotencyKey))
        if decisionDelay != .zero { try? await Task.sleep(for: decisionDelay) }
        approval.status = .approvedExecuted
        return approval
    }

    func deny(
        id: String, boundDigest: String, idempotencyKey: String,
        reason: DenialReason?, note: String?
    ) async throws -> Approval {
        denyCalls.append((id, idempotencyKey))
        if decisionDelay != .zero { try? await Task.sleep(for: decisionDelay) }
        approval.status = .denied
        return approval
    }

    func actions(limit: Int) async throws -> [ActionEvent] { [] }
    func receipts(since: Date?) async throws -> [ReceiptRecord] { [] }
    func exportBundle() async throws -> EvidenceBundle {
        EvidenceBundle(organization: "t", exportedAt: nil, publicKeyBase64: "", records: [])
    }
    func policy() async throws -> Policy {
        Policy(version: 1, resource: "refund.create",
               autoLimit: Money(minorUnits: 50_000), blockLimit: Money(minorUnits: 500_000),
               expirySeconds: 120, readableRule: "", updatedAt: Date())
    }
    func registerDevice(apnsToken: String, environment: String, deviceName: String, orgID: String) async throws {}
    func resetDemo() async throws {}
}

/// Counts refreshes and sign-outs so the 401 path can be asserted exactly (T-12).
actor RecordingSession: SessionProviding {
    private(set) var refreshCount = 0
    private(set) var signOutCount = 0
    private var token = "token-1"
    private let refreshSucceeds: Bool

    init(refreshSucceeds: Bool = true) {
        self.refreshSucceeds = refreshSucceeds
    }

    func accessToken() async throws -> String { token }

    func refresh() async throws -> String {
        refreshCount += 1
        guard refreshSucceeds else { throw WarrantError.unauthorized }
        token = "token-2"
        return token
    }

    func signOut() async { signOutCount += 1 }
}

/// Serves canned responses without a network.
///
/// Stubs are keyed by host, not held in one shared queue. Swift Testing runs suites in
/// parallel, and a single queue means one test eats another's responses — which is exactly
/// what happened the first time this was written, producing three failures that looked like
/// product bugs and were not.
///
/// `@unchecked Sendable` and `nonisolated(unsafe)` are justified here rather than assumed:
/// URLSession instantiates URLProtocol subclasses on threads we do not control, so the
/// registry cannot be actor-isolated and a lock is the only mechanism available.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: [Stub]] = [:]
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]

    /// A private host for one test, so nothing it does can be observed or consumed by another.
    static func makeHost() -> String { "test-\(UUID().uuidString.lowercased()).invalid" }

    static func register(host: String, stubs newStubs: [Stub]) {
        lock.lock(); defer { lock.unlock() }
        stubs[host] = newStubs
        requests[host] = []
    }

    static func recordedRequests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests[host] ?? []
    }

    private static func next(for request: URLRequest) -> Stub {
        lock.lock(); defer { lock.unlock() }
        guard let host = request.url?.host() else { return Stub(statusCode: 500, body: Data()) }
        requests[host, default: []].append(request)
        guard var queue = stubs[host], !queue.isEmpty else {
            return Stub(statusCode: 500, body: Data())
        }
        let stub = queue.removeFirst()
        stubs[host] = queue
        return stub
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let stub = Self.next(for: request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

enum Fixtures {
    static func approval(
        id: String = "wrt_4471",
        expiresIn seconds: TimeInterval = 120,
        now: Date = Date(),
        status: ApprovalStatus = .pending
    ) -> Approval {
        Approval(
            id: id, orgID: "org_1",
            actionLine: "Refund $2,400.00 to Northwind",
            amount: Money(minorUnits: 240_000),
            requestedBy: "Support Agent 01", resource: "payment_882",
            impact: "Money leaves the business account", reversibility: "Not reversible",
            whyReviewing: "Your rule caps automatic refunds at $500.",
            boundDigest: "sha256:4c1ea09f", createdAt: now,
            expiresAt: now.addingTimeInterval(seconds), status: status
        )
    }
}
