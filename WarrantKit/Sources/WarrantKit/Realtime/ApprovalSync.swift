import Foundation

/// Keeps the inbox current with two independent mechanisms running at once (§9.1).
///
/// Realtime is the fast path and polling is the floor — not a fallback that something has to
/// notice and trigger. Conference wifi drops mid-sentence, and a fallback that needs a healthy
/// connection to detect an unhealthy one is not a fallback. The poll runs regardless; Realtime
/// just makes it feel instant by nudging it early.
public actor ApprovalSync {
    public struct Snapshot: Sendable {
        public let approvals: [Approval]
        public let isOffline: Bool
        public let syncedAt: Date?
    }

    private let source: any WarrantDataSource
    private let cache: OfflineCache
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]

    public init(
        source: any WarrantDataSource,
        cache: OfflineCache,
        interval: Duration = .milliseconds(700)
    ) {
        self.source = source
        self.cache = cache
        self.interval = interval
    }

    public func snapshots() -> AsyncStream<Snapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }

    /// The poll floor. Every tick refreshes whether or not Realtime is connected.
    public func start() {
        guard task == nil else { return }
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Called by whatever Realtime client the app wires up, to refresh immediately rather
    /// than waiting for the next tick. Safe to call as often as it likes.
    public func realtimeDidChange() {
        Task { await refresh() }
    }

    public func refresh() async {
        do {
            let approvals = try await source.pendingApprovals()
            cache.store(approvals, for: .approvals)
            cache.store(approvals.count, for: .pendingCount)
            cache.markSynced()
            broadcast(Snapshot(approvals: approvals, isOffline: false, syncedAt: cache.lastSyncedAt))
        } catch {
            // Fail closed and say so. An empty inbox and an unreachable gateway look identical
            // on screen unless we insist otherwise, and one of them means "do not tap".
            let cached = cache.load([Approval].self, for: .approvals) ?? []
            broadcast(Snapshot(approvals: cached, isOffline: true, syncedAt: cache.lastSyncedAt))
        }
    }

    private func broadcast(_ snapshot: Snapshot) {
        for continuation in continuations.values { continuation.yield(snapshot) }
    }
}
