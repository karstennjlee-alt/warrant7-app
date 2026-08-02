import SwiftUI
import WidgetKit
import WarrantKit

struct WidgetSnapshot: TimelineEntry {
    let date: Date
    let pendingCount: Int
    let recordCount: Int
    let isChainVerified: Bool
}

struct PendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetSnapshot {
        WidgetSnapshot(date: Date(), pendingCount: 1, recordCount: 6, isChainVerified: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshot) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshot>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(60))))
    }

    /// Reads what the app cached in the shared container and verifies it here, in the widget's
    /// own process. The chain status shown is computed, not remembered.
    private func load() -> WidgetSnapshot {
        let cache = OfflineCache(appGroup: IntentConfiguration.appGroup)
        let pending = cache.load(Int.self, for: .pendingCount) ?? 0

        guard let data = cache.read(.bundle), let bundle = try? EvidenceBundle.parse(data) else {
            return WidgetSnapshot(date: Date(), pendingCount: pending, recordCount: 0, isChainVerified: true)
        }
        let report = ChainVerifier().verify(bundle: bundle)
        return WidgetSnapshot(
            date: Date(),
            pendingCount: pending,
            recordCount: report.records.count,
            isChainVerified: report.isVerified
        )
    }
}

struct PendingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WarrantPending", provider: PendingProvider()) { entry in
            PendingWidgetView(entry: entry)
                .containerBackground(Ink.canvas, for: .widget)
        }
        .configurationDisplayName("Approvals")
        .description("What's waiting on you, and whether the receipts still check out.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct PendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.pendingCount)")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                    Text("waiting")
                        .font(.system(size: 9))
                }
            }
            .widgetURL(URL(string: "\(Brand.scheme)://inbox"))
        default:
            VStack(alignment: .leading, spacing: 6) {
                StampGlyph(status: entry.pendingCount > 0 ? .pending : .approvedExecuted)
                    .frame(width: 18, height: 18)
                Spacer(minLength: 0)
                Text("\(entry.pendingCount)")
                    .font(.system(size: 40, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.ink)
                Text(entry.pendingCount == 1 ? "approval waiting" : "approvals waiting")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.soft)
                Spacer(minLength: 0)
                Text("\(entry.recordCount) records · \(entry.isChainVerified ? "verified" : "check failed")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(entry.isChainVerified ? Ink.green : Ink.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "\(Brand.scheme)://inbox"))
        }
    }
}

@main
struct WarrantWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PendingWidget()
        ApprovalLiveActivity()
    }
}
