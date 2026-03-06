import AppKit
import Foundation
import UserNotifications

/// Notification controller that surfaces queued completions to Notification Center.
final class AgentCompletionNotificationManager: NSObject, AgentCompletionNotificationManaging, UNUserNotificationCenterDelegate {
    var onActivateSurface: ((UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var notificationIdsBySurfaceId: [UUID: Set<String>] = [:]

    override init() {
        super.init()
        center.delegate = self
        requestAuthorizationIfNeeded()
    }

    /// Schedules a user-visible notification for a newly queued completion.
    func scheduleNotification(
        target: PendingCompletionTarget,
        workspaceName: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(target.surface.agentType.displayName) Finished Responding"
        content.subtitle = workspaceName
        content.body = target.surface.title
        content.sound = .default
        content.userInfo = [
            "surfaceId": target.surface.id.uuidString,
            "workspaceId": target.workspaceId.uuidString
        ]

        let identifier = "completion-\(target.sequence)-\(target.surface.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        center.add(request) { [weak self] error in
            guard error == nil else { return }
            Task { @MainActor in
                CompletionDebugLogger.log(
                    "scheduled notification id=\(identifier) surface=\(target.surface.id.uuidString)"
                )
                self?.notificationIdsBySurfaceId[target.surface.id, default: []].insert(identifier)
            }
        }
    }

    /// Removes any delivered notifications associated with a handled or closed surface.
    func removeNotifications(for surfaceId: UUID) {
        guard let identifiers = notificationIdsBySurfaceId.removeValue(forKey: surfaceId), !identifiers.isEmpty else {
            return
        }

        CompletionDebugLogger.log(
            "clearing notifications surface=\(surfaceId.uuidString) count=\(identifiers.count)"
        )
        center.removeDeliveredNotifications(withIdentifiers: Array(identifiers))
        center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))
    }

    /// Presents completion notifications even while the app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Focuses the clicked completion target if the notification belongs to a known surface.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let rawSurfaceId = response.notification.request.content.userInfo["surfaceId"] as? String,
              let surfaceId = UUID(uuidString: rawSurfaceId) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            self.removeNotifications(for: surfaceId)
            NSApplication.shared.activate(ignoringOtherApps: true)
            CompletionDebugLogger.log("notification click surface=\(surfaceId.uuidString)")
            self.onActivateSurface?(surfaceId)
            completionHandler()
        }
    }

    /// Requests notification authorization lazily during manager initialization.
    private func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
}
