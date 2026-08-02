import SwiftUI
import UserNotifications
import WarrantKit

@main
struct WarrantApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .tint(Ink.blue)
                .task {
                    delegate.state = state
                    await state.start()
                    await UNUserNotificationAdapter.registerCategories()
                }
                .onOpenURL { url in
                    Task { await state.handle(url: url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        state.takeIslandHandoff()
                        Task { await state.refreshApprovals() }
                    case .background:
                        // Nothing is left polling in the background: a decision made while the
                        // app is not on screen is a decision nobody watched.
                        state.stop()
                    default:
                        break
                    }
                }
        }
    }
}

/// Handles notification taps and the actionable Deny.
///
/// The delegate callbacks are `nonisolated` and extract only `Sendable` values before hopping
/// to the main actor. `UNNotificationResponse` is not `Sendable`, so it must not cross.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var state: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        guard let approvalID = response.notification.request.content.userInfo["approval_id"] as? String else {
            return
        }

        if actionIdentifier == NotificationCategory.deny {
            // Safe, so it can happen inline from a locked device without a foreground trip.
            await denyFromNotification(approvalID: approvalID)
        } else {
            // Everything else opens the card — including an approval that was already decided,
            // which shows its terminal state rather than an empty screen.
            await MainActor.run {
                state?.selectedTab = .inbox
                state?.presentedApprovalID = approvalID
            }
        }
    }

    private func denyFromNotification(approvalID: String) async {
        guard let state = await MainActor.run(body: { self.state }) else { return }
        let source = state.dataSource
        let coordinator = state.coordinator

        guard let approval = try? await source.approval(id: approvalID) else { return }
        guard let settled = try? await coordinator.submit(.deny(reason: nil, note: nil), for: approval) else { return }

        await MainActor.run { state.record(decision: settled) }
        await LiveActivityController.end(approvalID: approvalID, status: settled.status)
    }
}
