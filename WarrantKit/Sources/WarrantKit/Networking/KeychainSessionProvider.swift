import Foundation

/// Reads the session token the app stored, for processes that cannot run the full auth stack.
///
/// The widget extension is one such process: it has no Supabase client and no way to present a
/// sign-in. It can carry a token that already exists and it can be told no. It cannot refresh,
/// so a 401 here ends as a 401 rather than as a silent renewal — which is the correct outcome
/// for a process that cannot ask a person to sign in again.
public struct KeychainSessionProvider: SessionProviding {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func accessToken() async throws -> String {
        guard let token = try keychain.string(for: KeychainStore.Account.sessionToken) else {
            throw WarrantError.unauthorized
        }
        return token
    }

    public func refresh() async throws -> String {
        throw WarrantError.unauthorized
    }

    public func signOut() async {
        try? keychain.removeItem(for: KeychainStore.Account.sessionToken)
    }
}

/// Builds the data source for whichever process is asking.
///
/// The app and the widget extension both need one, and they must agree about demo mode or a
/// denial from the Dynamic Island would land somewhere the inbox never sees.
public enum DataSourceFactory {
    public static func make(
        apiBaseURL: URL?,
        appGroup: String,
        forceDemo: Bool = false
    ) -> any WarrantDataSource {
        guard !forceDemo, let apiBaseURL else {
            return DemoDataSource()
        }
        let client = APIClient(baseURL: apiBaseURL, sessionProvider: KeychainSessionProvider())
        return LiveDataSource(client: client, cache: OfflineCache(appGroup: appGroup))
    }
}
