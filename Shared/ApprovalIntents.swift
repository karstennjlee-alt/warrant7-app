import ActivityKit
import AppIntents
import Foundation
import WarrantKit

/// Compiled into both the app and the widget extension, so the buttons on the Live Activity
/// and the buttons on the card are running the same code with the same guards.
///
/// The asymmetry is the whole design: denial is safe to be one tap from a locked device;
/// approval is not, and never happens without a trip through the app and Face ID.
struct DenyApprovalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Deny"
    static let description = IntentDescription("Refuse this action. Nothing will be executed.")

    /// Deliberately false. Denial is the safe outcome, so it should cost one tap from the lock
    /// screen and no context switch.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Approval")
    var approvalID: String

    init() {}

    init(approvalID: String) {
        self.approvalID = approvalID
    }

    func perform() async throws -> some IntentResult {
        let source = DataSourceFactory.make(
            apiBaseURL: IntentConfiguration.apiBaseURL,
            appGroup: IntentConfiguration.appGroup
        )
        let coordinator = DecisionCoordinator(source: source)

        guard let approval = try? await source.approval(id: approvalID) else {
            return .result()
        }
        // Same local expiry guard as the card. A stale Live Activity must not be able to fire
        // a decision into a window that has already closed.
        guard approval.isActionable() else {
            await IntentConfiguration.endActivity(approvalID: approvalID, status: .expired)
            return .result()
        }

        if let settled = try? await coordinator.submit(.deny(reason: nil, note: nil), for: approval) {
            await IntentConfiguration.endActivity(approvalID: approvalID, status: settled.status)
        }
        return .result()
    }
}

/// Approving from the Island opens the app, every time, so the biometric gate cannot be
/// skipped. A one-tap approve from a locked device would be exactly the hole this product
/// exists to close.
struct ApproveApprovalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Approve once"
    static let description = IntentDescription("Open Warrant and confirm with Face ID.")

    static let openAppWhenRun: Bool = true

    @Parameter(title: "Approval")
    var approvalID: String

    init() {}

    init(approvalID: String) {
        self.approvalID = approvalID
    }

    func perform() async throws -> some IntentResult {
        // `openAppWhenRun` brings the app forward; this hands it the destination.
        // `OpenURLIntent` would be tidier but is iOS 18, and the floor here is 17.
        IntentConfiguration.handoff(approvalID: approvalID)
        return .result()
    }
}

enum IntentConfiguration {
    static var apiBaseURL: URL? {
        guard let raw = Bundle.main.infoDictionary?["WarrantAPIBaseURL"] as? String,
              !raw.contains("YOUR-"), !raw.contains("$("),
              let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }

    static var appGroup: String {
        "group." + (Bundle.main.bundleIdentifier?.replacingOccurrences(of: ".widgets", with: "") ?? "dev.warrant.app")
    }

    /// Where an Island approve leaves the approval id for the app to pick up.
    static let handoffKey = "WarrantPendingApprovalHandoff"

    static func handoff(approvalID: String) {
        UserDefaults(suiteName: appGroup)?.set(approvalID, forKey: handoffKey)
    }

    static func takeHandoff() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let id = defaults.string(forKey: handoffKey) else { return nil }
        defaults.removeObject(forKey: handoffKey)
        return id
    }

    @MainActor
    static func endActivity(approvalID: String, status: ApprovalStatus) async {
        for activity in Activity<ApprovalActivityAttributes>.activities
        where activity.attributes.approvalID == approvalID {
            let final = ApprovalActivityAttributes.ContentState(
                expiresAt: activity.content.state.expiresAt,
                status: status
            )
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now + 8))
        }
    }
}
