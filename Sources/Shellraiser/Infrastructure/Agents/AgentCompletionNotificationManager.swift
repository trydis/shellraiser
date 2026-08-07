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
        scheduleNotification(target: target, workspaceName: workspaceName, kind: .finished)
    }

    /// Schedules a user-visible notification of the given kind.
    func scheduleNotification(
        target: PendingCompletionTarget,
        workspaceName: String,
        kind: AgentNotificationKind
    ) {
        let title: String
        switch kind {
        case .finished:
            title = "\(target.surface.agentType.displayName) Finished Responding"
        case .waitingForInput:
            title = "\(target.surface.agentType.displayName) Needs Your Input"
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = workspaceName
        content.body = target.surface.title
        content.sound = .default
        content.userInfo = [
            "surfaceId": target.surface.id.uuidString,
            "workspaceId": target.workspaceId.uuidString
        ]

        let identifier = notificationIdentifier(for: target, kind: kind)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        // Recorded synchronously (we're already on the main actor here) so a
        // back-to-back duplicate event sees the identifier immediately instead of
        // racing UNUserNotificationCenter's asynchronous completion handler.
        notificationIdsBySurfaceId[target.surface.id, default: []].insert(identifier)
        CompletionDebugLogger.log(
            "scheduled notification id=\(identifier) surface=\(target.surface.id.uuidString)"
        )

        center.add(request) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.notificationIdsBySurfaceId[target.surface.id]?.remove(identifier)
            }
        }
    }

    /// Returns a stable identifier for waiting-for-input (one live banner per surface)
    /// and a sequence-scoped identifier for completion notifications.
    private func notificationIdentifier(for target: PendingCompletionTarget, kind: AgentNotificationKind) -> String {
        switch kind {
        case .finished:
            return "completion-\(target.sequence)-\(target.surface.id.uuidString)"
        case .waitingForInput:
            return "waiting-for-input-\(target.surface.id.uuidString)"
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
