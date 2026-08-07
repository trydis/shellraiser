import SwiftUI

/// Derived, read-only projection of a surface's current agent activity.
///
/// This is never persisted on `SurfaceModel` — always computed from
/// `WorkspaceManager`'s live `awaitingInputSurfaceIds` / `busySurfaceIds` sets and
/// `SurfaceModel.hasPendingCompletion` (see `WorkspaceManager.activityStatus(for:)`), so there
/// is no risk of drifting from the authoritative completion-tracking state that already backs
/// notifications and the dock badge.
enum SurfaceActivityStatus: Equatable, CaseIterable {
    /// Blocked on a permission prompt or approval — the agent is waiting on the operator right now.
    case needsInput
    /// A turn finished and is queued in the pending-completion FIFO awaiting review.
    case ready
    /// The agent is actively working on a turn.
    case running
    /// No queued completion, no pending input, and not currently busy.
    case idle

    /// Sort priority used by Agent HQ and other cross-workspace views; lower sorts first.
    var sortPriority: Int {
        switch self {
        case .needsInput: return 0
        case .ready: return 1
        case .running: return 2
        case .idle: return 3
        }
    }

    /// Human-readable label for status badges and accessibility strings.
    var displayName: String {
        switch self {
        case .needsInput: return "Needs Input"
        case .ready: return "Ready"
        case .running: return "Running"
        case .idle: return "Idle"
        }
    }

    /// SF Symbol used to represent this status in compact UI.
    var systemImage: String {
        switch self {
        case .needsInput: return "exclamationmark.bubble.fill"
        case .ready: return "bell.fill"
        case .running: return "circle.dashed"
        case .idle: return "circle"
        }
    }

    /// Tint color used to represent this status in compact UI.
    var tintColor: Color {
        switch self {
        case .needsInput: return .orange
        case .ready: return AppTheme.highlight
        case .running: return AppTheme.highlight
        case .idle: return AppTheme.textSecondary
        }
    }
}
