import Foundation

/// Last known good state, so the ledger and the Verify tab work in airplane mode (§9.4).
///
/// Deliberately not a database. This holds a handful of small JSON files that the widget
/// extension can also read, and losing it costs a refresh rather than any evidence.
public struct OfflineCache: Sendable {
    private let directory: URL
    private let appGroup: String?

    public init(appGroup: String? = nil) {
        self.appGroup = appGroup
        let base: URL
        if let appGroup,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            base = container
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        directory = base.appendingPathComponent("WarrantCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public enum Key: String, Sendable {
        case approvals
        case receipts
        case bundle
        case policy
        case activity
        case syncedAt
        case pendingCount
    }

    private func url(_ key: Key) -> URL {
        directory.appendingPathComponent("\(key.rawValue).json")
    }

    public func write(_ data: Data, for key: Key) {
        try? data.write(to: url(key), options: .atomic)
    }

    public func read(_ key: Key) -> Data? {
        try? Data(contentsOf: url(key))
    }

    public func store<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? WarrantJSON.encoder.encode(value) else { return }
        write(data, for: key)
    }

    public func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = read(key) else { return nil }
        return try? WarrantJSON.decoder.decode(type, from: data)
    }

    public func markSynced(at date: Date = Date()) {
        write(Data(WarrantJSON.string(from: date).utf8), for: .syncedAt)
    }

    public var lastSyncedAt: Date? {
        guard let data = read(.syncedAt), let text = String(data: data, encoding: .utf8) else { return nil }
        return WarrantJSON.date(from: text)
    }

    /// `OFFLINE · last synced 14s ago` — mono, because the app computed it (§8, §9.4).
    public func offlineStrip(now: Date = Date()) -> String {
        guard let synced = lastSyncedAt else { return "OFFLINE · never synced" }
        let seconds = Int(max(0, now.timeIntervalSince(synced)))
        let ago: String
        switch seconds {
        case ..<60: ago = "\(seconds)s"
        case ..<3600: ago = "\(seconds / 60)m"
        default: ago = "\(seconds / 3600)h"
        }
        return "OFFLINE · last synced \(ago) ago"
    }

    public func clear() {
        for key in [Key.approvals, .receipts, .bundle, .policy, .activity, .syncedAt, .pendingCount] {
            try? FileManager.default.removeItem(at: url(key))
        }
    }
}
