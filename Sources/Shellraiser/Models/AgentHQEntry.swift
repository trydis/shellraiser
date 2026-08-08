import Foundation

/// One row in the Agent HQ dashboard: a single surface flattened out of its owning workspace.
///
/// Built entirely from already-published `WorkspaceManager` state — never mounts a terminal view,
/// per the GPU-memory constraint documented in `docs/plans/memory-growth-gpu-iosurface.md`.
struct AgentHQEntry: Identifiable, Equatable {
    let workspaceId: UUID
    let workspaceName: String
    let paneId: UUID
    let surfaceId: UUID
    let title: String
    let agentType: AgentType
    let status: SurfaceActivityStatus
    let branchName: String?
    let isLinkedWorktree: Bool
    let progress: SurfaceProgressReport?
    let lastActivity: Date
    /// Last-activity summary resolved by `SessionSummaryService`; nil until read or unavailable.
    let summary: String?
    /// FIFO ordering key shared with the `Cmd+Shift+U` completion queue; nil unless `status == .ready`.
    let pendingCompletionSequence: Int?

    var id: UUID { surfaceId }
}

extension AgentHQEntry {
    /// Returns entries sorted in Agent HQ's global display order.
    ///
    /// Primary key is status priority (`needsInput` → `ready` → `running` → `idle`). Within
    /// `.ready`, ties break on the same FIFO `pendingCompletionSequence` used by
    /// `jumpToNextCompletedSession()` so the dashboard and the `Cmd+Shift+U` jump always agree.
    /// Every other tie breaks on most-recent activity first.
    static func sorted(_ entries: [AgentHQEntry]) -> [AgentHQEntry] {
        entries.sorted { lhs, rhs in
            if lhs.status.sortPriority != rhs.status.sortPriority {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }

            if lhs.status == .ready {
                let lhsSequence = lhs.pendingCompletionSequence ?? .max
                let rhsSequence = rhs.pendingCompletionSequence ?? .max
                if lhsSequence != rhsSequence {
                    return lhsSequence < rhsSequence
                }
            }

            return lhs.lastActivity > rhs.lastActivity
        }
    }
}
