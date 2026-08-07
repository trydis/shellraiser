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

/// Semantic kind of an agent-status notification.
enum AgentNotificationKind {
    /// The agent completed its turn normally.
    case finished
    /// The agent is blocked waiting for the user to approve a permission or answer a prompt.
    case waitingForInput
}

/// Notification manager contract consumed by the workspace manager.
protocol AgentCompletionNotificationManaging: AnyObject {
    /// Callback fired when the user activates a completion notification.
    var onActivateSurface: ((UUID) -> Void)? { get set }

    /// Schedules a user-visible completion notification.
    func scheduleNotification(target: PendingCompletionTarget, workspaceName: String)

    /// Schedules a user-visible notification of the given kind.
    func scheduleNotification(target: PendingCompletionTarget, workspaceName: String, kind: AgentNotificationKind)

    /// Removes pending and delivered notifications for a surface.
    func removeNotifications(for surfaceId: UUID)
}
