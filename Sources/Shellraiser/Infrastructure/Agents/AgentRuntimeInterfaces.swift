import Foundation

/// Minimal runtime bridge contract required by app orchestration.
@MainActor
protocol AgentRuntimeSupporting {
    /// Shared completion log used by managed agent wrappers.
    var eventLogURL: URL { get }

    /// Ensures runtime helper scripts and files are ready for use.
    func prepareRuntimeSupport()
}

/// Completion event monitor contract consumed by the workspace manager.
protocol AgentCompletionEventMonitoring: AnyObject {
    /// Callback fired for each parsed completion event.
    var onEvent: ((AgentCompletionEvent) -> Void)? { get set }
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
