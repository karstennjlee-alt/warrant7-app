import Foundation
import UIKit
import UserNotifications
import WarrantKit

/// The real `UNUserNotificationCenter`, behind the seam WarrantKit defines.
public struct UNUserNotificationAdapter: UserNotificationScheduling {

    public init() {}

    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func schedule(
        id: String, title: String, body: String, categoryID: String,
        userInfo: [String: String], expiresAt: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        content.userInfo = userInfo
        content.sound = .default
        // A 120 second window that a Focus mode can silence is a window that closes without
        // anyone seeing it. Nothing else in this app is allowed to use this level.
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Deny inline, Review opens the app.
    ///
    /// There is deliberately no Approve action. A notification action cannot present Face ID,
    /// so an inline approve would be an approval without the one check that makes approving
    /// meaningful.
    public static func registerCategories() async {
        let deny = UNNotificationAction(
            identifier: NotificationCategory.deny,
            title: "Deny",
            options: [.destructive]
        )
        let review = UNNotificationAction(
            identifier: NotificationCategory.review,
            title: "Review",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.approval,
            actions: [deny, review],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor
    public static func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    public static func authorizationState() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
