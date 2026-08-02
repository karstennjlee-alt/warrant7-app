import Foundation
import Supabase
import WarrantKit

/// Auth and Realtime. The device holds a session token and nothing else.
public final class SupabaseService: Sendable {
    public let client: SupabaseClient
    private let keychain: KeychainStore

    public init(url: URL, anonKey: String, keychain: KeychainStore = KeychainStore()) {
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        self.keychain = keychain
    }

    // MARK: - Auth

    /// Email and password.
    ///
    /// Preferred over the magic link on a phone, and not merely as a convenience: the link
    /// needs SMTP configured and a redirect allowlist that points at something the handset can
    /// open. Until both are set, a magic link is a sign-in that silently never arrives, and a
    /// password is a sign-in that works.
    @discardableResult
    public func signIn(email: String, password: String) async throws -> String {
        let session = try await client.auth.signIn(email: email, password: password)
        try persist(accessToken: session.accessToken)
        try? keychain.setString(email, for: KeychainStore.Account.signedInEmail)
        return session.accessToken
    }

    public var storedEmail: String? {
        try? keychain.string(for: KeychainStore.Account.signedInEmail)
    }

    /// Magic link. The redirect comes back as `warrant://auth-callback`.
    public func sendMagicLink(to email: String) async throws {
        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: URL(string: "\(Brand.scheme)://auth-callback")
        )
    }

    /// Completes sign-in from the deep link the mail app opened.
    public func completeSignIn(from url: URL) async throws {
        let session = try await client.auth.session(from: url)
        try persist(accessToken: session.accessToken)
    }

    public func currentSession() async -> Bool {
        (try? await client.auth.session) != nil
    }

    public func signOut() async {
        try? await client.auth.signOut()
        try? keychain.removeItem(for: KeychainStore.Account.sessionToken)
        try? keychain.removeItem(for: KeychainStore.Account.refreshToken)
        try? keychain.removeItem(for: KeychainStore.Account.signedInEmail)
    }

    /// Mirrored into the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so
    /// a background refresh can reach it after first unlock and a backup never can.
    private func persist(accessToken: String) throws {
        try keychain.setString(accessToken, for: KeychainStore.Account.sessionToken)
    }

    // MARK: - Realtime

    /// Subscribes to this org's approvals and calls back on any change.
    ///
    /// This is the fast path only. ``ApprovalSync`` polls underneath it regardless, so losing
    /// this subscription costs latency rather than correctness (§9.1).
    public func observeApprovals(orgID: String, onChange: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {
            let channel = client.channel("approvals:\(orgID)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "approvals",
                filter: .eq("org_id", value: orgID)
            )
            do {
                try await channel.subscribeWithError()
            } catch {
                // §9.1: the poll underneath is the correctness path, so a failed subscribe
                // costs latency and nothing else. Give up the fast path quietly.
                await client.removeChannel(channel)
                return
            }
            for await _ in changes {
                if Task.isCancelled { break }
                await onChange()
            }
            await client.removeChannel(channel)
        }
    }
}

/// Adapts Supabase's session to the gateway client, which knows nothing about Supabase.
public struct SupabaseSessionProvider: SessionProviding {
    private let service: SupabaseService

    public init(service: SupabaseService) {
        self.service = service
    }

    public func accessToken() async throws -> String {
        try await service.client.auth.session.accessToken
    }

    public func refresh() async throws -> String {
        try await service.client.auth.refreshSession().accessToken
    }

    public func signOut() async {
        await service.signOut()
    }
}

/// Used when nothing is configured. Every call fails as unauthorized, which keeps the live
/// path honest instead of quietly succeeding against nothing.
public struct UnconfiguredSessionProvider: SessionProviding {
    public init() {}
    public func accessToken() async throws -> String { throw WarrantError.notConfigured }
    public func refresh() async throws -> String { throw WarrantError.notConfigured }
    public func signOut() async {}
}
