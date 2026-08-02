import Testing
import Foundation
@testable import WarrantKit

@Suite("T-09…T-11 · Decisions, expiry, and double taps")
struct DecisionTests {

    // MARK: - T-09

    @Test("T-09 · Actionable one second before expiry, not actionable at expiry")
    func expiryMath() {
        let now = Date()
        let approval = Fixtures.approval(expiresIn: 120, now: now)

        #expect(approval.isActionable(at: approval.expiresAt.addingTimeInterval(-1)))
        // Fail closed: the boundary belongs to expiry, not to the approver.
        #expect(!approval.isActionable(at: approval.expiresAt))
        #expect(!approval.isActionable(at: approval.expiresAt.addingTimeInterval(1)))
    }

    @Test("T-09 · Seconds remaining never goes negative")
    func secondsRemainingFloor() {
        let approval = Fixtures.approval(expiresIn: 10)
        #expect(approval.secondsRemaining(at: approval.expiresAt.addingTimeInterval(60)) == 0)
    }

    @Test("T-09 · A decided approval is not actionable however much time is left")
    func decidedIsNotActionable() {
        let approval = Fixtures.approval(expiresIn: 120, status: .denied)
        #expect(!approval.isActionable(at: Date()))
    }

    // MARK: - T-10

    @Test("T-10 · A double tap produces exactly one call with exactly one idempotency key")
    func doubleTapApprove() async throws {
        let approval = Fixtures.approval()
        let source = RecordingDataSource(approval: approval)
        await source.setDecisionDelay(.milliseconds(120))
        let coordinator = DecisionCoordinator(source: source)

        async let first = coordinator.submit(.approve, for: approval)
        // Long enough to be inside the first call's window, short enough to be a real double tap.
        try? await Task.sleep(for: .milliseconds(20))
        async let second = coordinator.submit(.approve, for: approval)

        let results = try await [first, second]
        let calls = await source.approveCalls

        #expect(calls.count == 1, "the second tap must be dropped, not queued")
        #expect(results.compactMap { $0 }.count == 1)
        #expect(Set(calls.map(\.key)).count == 1)
    }

    @Test("T-10 · A retry reuses the same idempotency key")
    func idempotencyKeyIsStable() async {
        let coordinator = DecisionCoordinator(source: RecordingDataSource(approval: Fixtures.approval()))
        let first = await coordinator.idempotencyKey(for: "wrt_4471")
        let second = await coordinator.idempotencyKey(for: "wrt_4471")
        #expect(first == second)
        // A different approval is a different action and must never share a key.
        let other = await coordinator.idempotencyKey(for: "wrt_4472")
        #expect(other != first)
    }

    // MARK: - T-11

    @Test("T-11 · A decision on an expired approval is blocked locally, with no request sent")
    func expiredDecisionSendsNothing() async throws {
        let now = Date()
        let approval = Fixtures.approval(expiresIn: 120, now: now)
        let source = RecordingDataSource(approval: approval)
        let coordinator = DecisionCoordinator(source: source)

        await #expect(throws: WarrantError.locallyExpired) {
            _ = try await coordinator.submit(.approve, for: approval, now: approval.expiresAt)
        }

        let calls = await source.approveCalls
        // The point of the guard: no call can race into a window the server still thinks is open.
        #expect(calls.isEmpty)
    }

    @Test("T-11 · Denying an expired approval is blocked too")
    func expiredDenialSendsNothing() async throws {
        let approval = Fixtures.approval()
        let source = RecordingDataSource(approval: approval)
        let coordinator = DecisionCoordinator(source: source)

        await #expect(throws: WarrantError.locallyExpired) {
            _ = try await coordinator.submit(
                .deny(reason: .promptInjection, note: nil), for: approval, now: approval.expiresAt
            )
        }
        #expect(await source.denyCalls.isEmpty)
    }

    @Test("Deny inside the window does go through, with a reason")
    func denyWorks() async throws {
        let approval = Fixtures.approval()
        let source = RecordingDataSource(approval: approval)
        let coordinator = DecisionCoordinator(source: source)

        let settled = try await coordinator.submit(
            .deny(reason: .promptInjection, note: "Call the customer first."), for: approval
        )

        #expect(settled?.status == .denied)
        #expect(await source.denyCalls.count == 1)
    }
}

@Suite("T-12 · Session handling")
struct SessionTests {

    /// Each test gets its own host so parallel suites cannot consume each other's stubs.
    func client(
        stubs: [MockURLProtocol.Stub],
        session provider: RecordingSession
    ) -> (client: APIClient, host: String) {
        let host = MockURLProtocol.makeHost()
        MockURLProtocol.register(host: host, stubs: stubs)
        return (
            APIClient(
                baseURL: URL(string: "https://\(host)")!,
                sessionProvider: provider,
                session: MockURLProtocol.session()
            ),
            host
        )
    }

    @Test("T-12 · A 401 refreshes once, retries once, and then signs out cleanly")
    func unauthorizedPath() async throws {
        let provider = RecordingSession()
        let (api, _) = client(
            stubs: [
                .init(statusCode: 401, body: Data()),
                .init(statusCode: 401, body: Data())
            ],
            session: provider
        )

        await #expect(throws: WarrantError.unauthorized) {
            _ = try await api.send(.me)
        }

        #expect(await provider.refreshCount == 1, "exactly one refresh — never a loop")
        #expect(await api.requestCount == 2, "the original and one retry, nothing more")
        #expect(await provider.signOutCount == 1)
    }

    @Test("T-12 · A 401 that the refresh fixes does not sign the person out")
    func refreshRecovers() async throws {
        let provider = RecordingSession()
        let body = Data(#"{"user":{"id":"u","email":"e@example.com"},"organizations":[]}"#.utf8)
        let (api, _) = client(
            stubs: [
                .init(statusCode: 401, body: Data()),
                .init(statusCode: 200, body: body)
            ],
            session: provider
        )

        let me = try await api.send(.me, as: MeResponse.self)

        #expect(me.user.email == "e@example.com")
        #expect(await provider.refreshCount == 1)
        #expect(await provider.signOutCount == 0)
    }

    @Test("Reason codes in the body beat the status code")
    func reasonCodeMapping() async throws {
        let provider = RecordingSession()
        let (api, _) = client(
            stubs: [.init(statusCode: 409, body: Data(#"{"code":"ALREADY_CONSUMED"}"#.utf8))],
            session: provider
        )

        await #expect(throws: WarrantError.alreadyConsumed) {
            _ = try await api.send(.me)
        }
    }

    @Test("Every mapped code has its own sentence, and none leaks a code")
    func errorMessagesAreHuman() {
        let mapped: [WarrantError] = [
            .approvalExpired, .alreadyConsumed, .digestMismatch, .humanDenied, .network
        ]
        #expect(Set(mapped.map(\.message)).count == mapped.count)

        for error in mapped {
            #expect(!error.message.contains("_"), "\(error) leaks a reason code")
            #expect(!error.message.lowercased().hasPrefix("error"))
        }
        // §4: the one an unsure approver reads before tapping again.
        #expect(WarrantError.network.message.contains("Nothing was approved"))
    }

    @Test("Requests carry the client header and an idempotency key on decisions")
    func headers() async throws {
        let provider = RecordingSession()
        let (api, host) = client(stubs: [.init(statusCode: 200, body: Data("{}".utf8))], session: provider)

        _ = try? await api.send(.approve(id: "a", boundDigest: "sha256:x", idempotencyKey: "key-1"))

        let request = MockURLProtocol.recordedRequests(host: host).first
        #expect(request?.value(forHTTPHeaderField: "X-Warrant-Client")?.hasPrefix("ios/") == true)
        #expect(request?.value(forHTTPHeaderField: "Idempotency-Key") == "key-1")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }
}
