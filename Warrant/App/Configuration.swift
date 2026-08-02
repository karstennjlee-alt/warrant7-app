import Foundation
import WarrantKit

/// Non-secret configuration, read from Info.plist where `Config.xcconfig` put it.
///
/// The Supabase anon key is publishable by design: it identifies the project rather than a
/// user, and everything it can reach is behind Row Level Security. It is not a leak, and it
/// should not be "fixed" later by moving it server-side. What is never here — not in this
/// file, not in Info.plist, not in the bundle — is a service-role key, a downstream provider
/// credential, or the ledger signing key.
public struct AppConfiguration: Sendable {
    public let apiBaseURL: URL?
    public let supabaseURL: URL?
    public let supabaseAnonKey: String?
    /// Dev-only bearer token, shared with a locally-run gateway. Debug builds only.
    public let devToken: String?
    public let appGroup: String

    public static let current = AppConfiguration()

    private init() {
        let info = Bundle.main.infoDictionary
        apiBaseURL = Self.url(info?["WarrantAPIBaseURL"] as? String)
        supabaseURL = Self.url(info?["WarrantSupabaseURL"] as? String)
        supabaseAnonKey = Self.value(info?["WarrantSupabaseAnonKey"] as? String)
        #if DEBUG
        devToken = Self.value(info?["WarrantDevToken"] as? String)
        #else
        // A shared static token is a development convenience and has no business in a
        // shipping build, so it is compiled out rather than merely left unset.
        devToken = nil
        #endif
        appGroup = "group." + (Bundle.main.bundleIdentifier ?? "dev.warrant.app")
    }

    /// Placeholders count as absent. A base URL of `https://YOUR-GATEWAY-HOST` is worse than
    /// no base URL, because it fails at request time instead of at launch.
    private static func value(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let placeholders = ["xxxx", "your-", "YOUR-", "warrant.app", "$(", "example.com"]
        guard !placeholders.contains(where: trimmed.contains) else { return nil }
        return trimmed
    }

    private static func url(_ raw: String?) -> URL? {
        guard let text = value(raw), let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    /// True when there is nothing real to talk to.
    ///
    /// The app then runs on ``DemoDataSource``, which is a specified feature rather than a
    /// stub: the story is complete, the signatures are real, and verification really passes
    /// and really fails. It is not the network layer routed around.
    /// Whether there is a real gateway to talk to, and some way to authenticate against it.
    ///
    /// The gateway is non-negotiable: it owns every piece of data the app renders, so without
    /// it there is nothing to show and the demo path is the honest answer. Authentication can
    /// come from Supabase or, in a Debug build against a local gateway, from ``devToken``.
    public var isFullyConfigured: Bool {
        apiBaseURL != nil && (hasSupabase || devToken != nil)
    }

    public var hasSupabase: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    /// What is missing, in the words of the config file, for Settings to show.
    public var missingKeys: [String] {
        var missing: [String] = []
        if apiBaseURL == nil { missing.append("API_BASE_URL") }
        if !hasSupabase && devToken == nil { missing.append("SUPABASE_URL + SUPABASE_ANON_KEY") }
        return missing
    }

    public static var isDemoLaunchArgument: Bool {
        UserDefaults.standard.bool(forKey: "WarrantDemoMode")
            || ProcessInfo.processInfo.arguments.contains("-WarrantDemoMode")
    }
}
