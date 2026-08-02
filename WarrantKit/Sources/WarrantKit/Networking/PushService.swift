import Foundation

/// Push is an enhancement, never a dependency (§1 rule 8).
///
/// Remote push and remote Live Activity updates need a paid Apple Developer account and an
/// APNs key. Everything is behind this protocol so the app is fully demoable without one, and
/// so adding one later is a registration change rather than a refactor.
public protocol PushService: Sendable {
    var isRemote: Bool { get }
    func requestAuthorization() async -> Bool
    /// Raise an alert for a newly pending approval. Local implementations post a local
    /// notification; the remote implementation does nothing, because APNs already did.
    func announce(approval: Approval, orgName: String) async
    func clearAnnouncement(approvalID: String) async
}

/// The no-paid-account path: Realtime plus polling notices the approval, and a local
/// notification raises it. Same category, same actions, same deep link as the remote one —
/// only the delivery differs.
public struct LocalPushService: PushService {
    public let isRemote = false
    private let center: any UserNotificationScheduling

    public init(center: any UserNotificationScheduling) {
        self.center = center
    }

    public func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    public func announce(approval: Approval, orgName: String) async {
        await center.schedule(
            id: approval.id,
            title: "\(orgName) needs a decision",
            body: "\(approval.actionLine). \(approval.whyReviewing)",
            categoryID: NotificationCategory.approval,
            userInfo: ["approval_id": approval.id],
            expiresAt: approval.expiresAt
        )
    }

    public func clearAnnouncement(approvalID: String) async {
        await center.cancel(id: approvalID)
    }
}

/// Thin seam over `UNUserNotificationCenter`, which does not exist in a test process.
public protocol UserNotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func schedule(
        id: String, title: String, body: String, categoryID: String,
        userInfo: [String: String], expiresAt: Date
    ) async
    func cancel(id: String) async
}

public enum NotificationCategory {
    public static let approval = "WARRANT_APPROVAL"

    /// Deny is inline and background; Review opens the app.
    ///
    /// There is deliberately **no approve action here** (§7). Naming the safe action inline
    /// and making the risky one take a trip through the app and Face ID is the correct
    /// asymmetry — and a notification action cannot present biometrics anyway.
    public static let deny = "DENY"
    public static let review = "REVIEW"
}
