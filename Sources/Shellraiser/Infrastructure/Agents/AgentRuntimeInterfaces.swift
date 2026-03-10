import Foundation

/// Minimal runtime bridge contract required by app orchestration.
@MainActor
protocol AgentRuntimeSupporting {
    /// Shared activity log used by managed agent wrappers.
    var eventLogURL: URL { get }

    /// Ensures runtime helper scripts and files are ready for use.
    func prepareRuntimeSupport()
}

/// Activity event monitor contract consumed by the workspace manager.
protocol AgentActivityEventMonitoring: AnyObject {
    /// Callback fired for each parsed runtime activity event.
    var onEvent: ((AgentActivityEvent) -> Void)? { get set }
}

/// Notification manager contract consumed by the workspace manager.
protocol AgentCompletionNotificationManaging: AnyObject {
    /// Callback fired when the user activates a completion notification.
    var onActivateSurface: ((UUID) -> Void)? { get set }

    /// Schedules a user-visible completion notification.
    func scheduleNotification(target: PendingCompletionTarget, workspaceName: String)

    /// Removes pending and delivered notifications for a surface.
    func removeNotifications(for surfaceId: UUID)
}
