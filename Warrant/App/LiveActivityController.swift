import ActivityKit
import Foundation
import WarrantKit

/// Starts, updates and ends the Live Activity for a pending approval.
///
/// A pending approval is a live, expiring, single-outcome event, which is exactly what
/// ActivityKit exists for. Remote updates need APNs; everything here works locally without it.
///
/// Deliberately stateless. Holding `Activity` objects in a main-actor dictionary and then
/// awaiting on them means handing a non-Sendable value across isolation on every call;
/// ActivityKit already keeps the authoritative list, so this reads from there instead.
public enum LiveActivityController {

    public static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static func activity(for approvalID: String) -> Activity<ApprovalActivityAttributes>? {
        Activity<ApprovalActivityAttributes>.activities
            .first { $0.attributes.approvalID == approvalID }
    }

    public static func start(approval: Approval, orgName: String) async {
        guard isAvailable, activity(for: approval.id) == nil else { return }

        let attributes = ApprovalActivityAttributes(approval: approval, orgName: orgName)
        let state = ApprovalActivityAttributes.ContentState(expiresAt: approval.expiresAt, status: .pending)

        // A Live Activity that will not start is a missing convenience, never a missing
        // decision: the card, the inbox and the notification all still work.
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: approval.expiresAt),
            pushType: nil
        )
    }

    public static func end(approvalID: String, status: ApprovalStatus) async {
        guard let activity = activity(for: approvalID) else { return }
        let final = ApprovalActivityAttributes.ContentState(
            expiresAt: activity.content.state.expiresAt,
            status: status
        )
        // Leave the outcome up for a beat rather than having it vanish the instant it lands.
        await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now + 8))
    }

    /// Keeps activities in step with the inbox: start one for anything newly pending, end any
    /// whose approval has left the list.
    public static func reconcile(pending: [Approval], orgName: String) async {
        for approval in pending {
            await start(approval: approval, orgName: orgName)
        }
        let pendingIDs = Set(pending.map(\.id))
        for activity in Activity<ApprovalActivityAttributes>.activities
        where !pendingIDs.contains(activity.attributes.approvalID) {
            await end(approvalID: activity.attributes.approvalID, status: .expired)
        }
    }
}
