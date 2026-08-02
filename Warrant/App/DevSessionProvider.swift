import Foundation
import WarrantKit

/// A fixed bearer token, for running against a gateway on this machine.
///
/// It exists because the alternative — a Supabase magic link — needs an email round-trip and a
/// redirect allowlist configured in a dashboard, neither of which belongs in the inner loop of
/// building the approval flow. The gateway checks this token exactly the way it will check a
/// real session, so nothing downstream of `APIClient` can tell the difference.
///
/// It never reaches a shipping build: `AppConfiguration.devToken` is compiled out except in
/// Debug, and `Config.xcconfig` is gitignored.
struct DevSessionProvider: SessionProviding {
    let token: String

    func accessToken() async throws -> String { token }

    /// There is nothing to refresh — a static token either works or the gateway is gone. That
    /// makes a 401 here a real 401, which is what the retry path should see.
    func refresh() async throws -> String { throw WarrantError.unauthorized }

    func signOut() async {}
}
