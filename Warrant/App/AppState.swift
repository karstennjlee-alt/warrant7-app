import Foundation
import Observation
import SwiftUI
import WarrantKit

/// Where the app keeps what it knows.
///
/// One object, on the main actor, holding the current snapshot of the world plus the services
/// that refresh it. Views read from here and never talk to the network themselves.
@MainActor
@Observable
public final class AppState {

    // What we know
    public private(set) var approvals: [Approval] = []
    public private(set) var recentDecisions: [Approval] = []
    public private(set) var activity: [ActionEvent] = []
    public private(set) var receipts: [ReceiptRecord] = []
    public private(set) var policy: Policy?
    public private(set) var organization: Organization?
    public private(set) var user: CurrentUser?
    public private(set) var publicKeyBase64: String?

    public private(set) var isOffline = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var isSignedIn = false

    /// Set when the app is running on ``DemoDataSource`` — either because nothing is
    /// configured or because demo mode was chosen deliberately.
    public private(set) var isDemoMode: Bool

    public var route = NavigationPath()
    public var selectedTab: Tab = .inbox
    public var presentedApprovalID: String?
    public var banner: String?

    // Services
    public let configuration = AppConfiguration.current
    public let verifier = ChainVerifier()
    public let biometrics = BiometricGate()
    public private(set) var dataSource: any WarrantDataSource
    public private(set) var coordinator: DecisionCoordinator
    private let cache: OfflineCache
    private var sync: ApprovalSync?
    private var syncTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private let supabase: SupabaseService?
    private let client: APIClient?

    /// warrant7 names almost everything differently and wraps its collections, so it gets its
    /// own translation rather than the app's model being bent to one server's vocabulary.
    static func liveSource(
        baseURL: URL, client: APIClient, cache: OfflineCache, email: String
    ) -> any WarrantDataSource {
        if baseURL.host()?.contains("warrant7") == true {
            return Warrant7DataSource(client: client, cache: cache, email: email)
        }
        return LiveDataSource(client: client, cache: cache)
    }

    public enum Tab: Hashable { case inbox, receipts, verify, policy, lab }

    public init() {
        let configuration = AppConfiguration.current
        cache = OfflineCache(appGroup: configuration.appGroup)
        let source: any WarrantDataSource

        if configuration.isFullyConfigured, !AppConfiguration.isDemoLaunchArgument,
           let apiBaseURL = configuration.apiBaseURL {
            // Supabase is still built when configured — Realtime uses it — but the dev token
            // wins for *authentication* when present. A magic link needs an email round-trip
            // and a dashboard redirect allowlist, so if a developer has deliberately set a dev
            // token, stopping at a sign-in screen they cannot complete helps nobody.
            let service = configuration.supabaseURL.flatMap { url in
                configuration.supabaseAnonKey.map { SupabaseService(url: url, anonKey: $0) }
            }
            supabase = service

            let provider: any SessionProviding
            if let devToken = configuration.devToken {
                provider = DevSessionProvider(token: devToken)
            } else if let service {
                provider = SupabaseSessionProvider(service: service)
            } else {
                provider = UnconfiguredSessionProvider()
            }
            let client = APIClient(baseURL: apiBaseURL, sessionProvider: provider)
            self.client = client
            source = Self.liveSource(baseURL: apiBaseURL, client: client, cache: cache, email: service?.storedEmail ?? "")
            isDemoMode = false
        } else {
            // Not a stub around a missing base URL — the specified demo path, whose outcomes
            // are real local state and whose signatures really verify (§9.2).
            supabase = nil
            self.client = nil
            source = DemoDataSource()
            isDemoMode = true
        }
        dataSource = source
        coordinator = DecisionCoordinator(source: source)
    }

    // MARK: - Lifecycle

    public func start() async {
        WarrantFonts.verifyRegistration()
        if isDemoMode {
            isSignedIn = true
        } else if configuration.devToken != nil {
            // The dev token is the session.
            isSignedIn = true
        } else if let supabase {
            isSignedIn = await supabase.currentSession()
            if isSignedIn, let email = supabase.storedEmail { rebuildSource(email: email) }
        }
        guard isSignedIn else { return }

        await loadEverything()
        startSync()
        takeIslandHandoff()
    }

    /// An approve tapped on the Dynamic Island opens the app and leaves the approval id here.
    /// It routes to the card and stops — the biometric gate still stands in front of the
    /// decision, which is the entire reason the Island cannot approve on its own.
    func takeIslandHandoff() {
        guard let id = IntentConfiguration.takeHandoff() else { return }
        selectedTab = .inbox
        presentedApprovalID = id
    }

    private func startSync() {
        guard sync == nil else { return }
        let sync = ApprovalSync(source: dataSource, cache: cache)
        self.sync = sync

        syncTask = Task { [weak self] in
            await sync.start()
            for await snapshot in await sync.snapshots() {
                guard let self else { return }
                self.apply(snapshot)
            }
        }

        if let supabase, let orgID = organization?.id {
            realtimeTask = supabase.observeApprovals(orgID: orgID) { [weak sync] in
                await sync?.realtimeDidChange()
            }
        }
    }

    private func apply(_ snapshot: ApprovalSync.Snapshot) {
        let pending = snapshot.approvals.filter { $0.status == .pending }
        approvals = pending.sorted { $0.expiresAt < $1.expiresAt }
        isOffline = snapshot.isOffline
        lastSyncedAt = snapshot.syncedAt
        UNUserNotificationAdapter.setBadge(pending.count)
    }

    public func stop() {
        syncTask?.cancel()
        realtimeTask?.cancel()
        Task { [sync] in await sync?.stop() }
        syncTask = nil
        realtimeTask = nil
        sync = nil
    }

    // MARK: - Loading

    public func loadEverything() async {
        // Identity first, and not merely for tidiness. Some gateways gate every read on a
        // membership row that this call creates, so firing the others concurrently means they
        // race it and lose — and a 403 renders as "offline", which is a lie about the network.
        await loadMe()

        async let approvals: Void = refreshApprovals()
        async let policy: Void = loadPolicy()
        async let activity: Void = loadActivity()
        async let receipts: Void = loadReceipts()
        _ = await (approvals, policy, activity, receipts)
    }

    public func loadMe() async {
        guard let response = try? await dataSource.me() else { return }
        user = response.user
        organization = response.organizations.first
    }

    public func refreshApprovals() async {
        do {
            let all = try await dataSource.pendingApprovals()
            approvals = all.filter { $0.status == .pending }.sorted { $0.expiresAt < $1.expiresAt }
            isOffline = false
            lastSyncedAt = Date()
        } catch {
            // The strip only ever says OFFLINE, because a person cannot act on a status code.
            // A developer can, so the reason goes to the console in Debug builds.
            #if DEBUG
            NSLog("[Warrant] approvals fetch failed: " + String(describing: error))
            #endif
            isOffline = true
            approvals = cache.load([Approval].self, for: .approvals) ?? approvals
            lastSyncedAt = cache.lastSyncedAt
        }
        UNUserNotificationAdapter.setBadge(approvals.count)
    }

    public func loadPolicy() async {
        policy = (try? await dataSource.policy()) ?? cache.load(Policy.self, for: .policy)
    }

    public func loadActivity() async {
        activity = ((try? await dataSource.actions(limit: 50)) ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    public func loadReceipts() async {
        receipts = ((try? await dataSource.receipts(since: nil)) ?? []).sorted { $0.sequence < $1.sequence }
        if let bundle = try? await dataSource.exportBundle() {
            publicKeyBase64 = bundle.publicKeyBase64
            try? PublicKeyStore().store(base64: bundle.publicKeyBase64)
        }
    }

    public func bundle() async -> EvidenceBundle? {
        try? await dataSource.exportBundle()
    }

    // MARK: - Decisions

    public func record(decision approval: Approval) {
        approvals.removeAll { $0.id == approval.id }
        recentDecisions.insert(approval, at: 0)
        recentDecisions = Array(recentDecisions.prefix(20))
        UNUserNotificationAdapter.setBadge(approvals.count)
        Task {
            await loadReceipts()
            await loadActivity()
        }
    }

    public func approval(id: String) -> Approval? {
        approvals.first { $0.id == id } ?? recentDecisions.first { $0.id == id }
    }

    // MARK: - Session

    public func signIn(email: String) async throws {
        guard let supabase else { throw WarrantError.notConfigured }
        try await supabase.sendMagicLink(to: email)
    }

    /// Email and password, which is the path that actually works on a handset today.
    public func signIn(email: String, password: String) async throws {
        guard let supabase else { throw WarrantError.notConfigured }
        try await supabase.signIn(email: email, password: password)
        rebuildSource(email: email)
        isSignedIn = true
        await loadEverything()
        startSync()
    }

    /// The data source carries the signed-in identity, so it is rebuilt once that is known.
    private func rebuildSource(email: String) {
        guard let apiBaseURL = configuration.apiBaseURL, let client else { return }
        dataSource = Self.liveSource(baseURL: apiBaseURL, client: client, cache: cache, email: email)
        coordinator = DecisionCoordinator(source: dataSource)
    }

    public func handle(url: URL) async {
        // warrant://approval/<id>
        if url.host == "approval", let id = url.pathComponents.last, id != "/" {
            selectedTab = .inbox
            presentedApprovalID = id
            return
        }
        // warrant://demo/act2 — one scan back to the pending approval, mid demo.
        if url.host == "demo" {
            try? await (dataSource as? DemoDataSource)?.resetDemo()
            await refreshApprovals()
            selectedTab = .inbox
            presentedApprovalID = approvals.first?.id
            return
        }
        if url.host == "auth-callback", let supabase {
            try? await supabase.completeSignIn(from: url)
            isSignedIn = await supabase.currentSession()
            if isSignedIn {
                await loadEverything()
                startSync()
            }
        }
    }

    public func signOut() async {
        stop()
        await supabase?.signOut()
        try? PublicKeyStore().clear()
        cache.clear()
        isSignedIn = false
        approvals = []
        recentDecisions = []
        receipts = []
        activity = []
    }

    public func resetDemo() async {
        try? await dataSource.resetDemo()
        for approval in recentDecisions { await coordinator.forget(approval.id) }
        recentDecisions = []
        await loadEverything()
    }

    public var offlineStrip: String {
        cache.offlineStrip()
    }
}
