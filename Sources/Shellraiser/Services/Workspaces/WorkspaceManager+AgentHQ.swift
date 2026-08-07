import Foundation

/// Builds the flattened, globally-sorted cross-workspace session list for Agent HQ.
extension WorkspaceManager {
    /// Returns every live surface across all workspaces as Agent HQ rows, in display order.
    ///
    /// Reads only already-published manager state (`gitStatesBySurfaceId`, `progressBySurfaceId`,
    /// `sessionSummariesBySurfaceId`, and the busy/awaiting-input sets via `activityStatus(for:)`) —
    /// never mounts a terminal view.
    func agentHQEntries() -> [AgentHQEntry] {
        let entries = workspaces.flatMap { workspace -> [AgentHQEntry] in
            workspace.rootPane.allSurfaceIds().compactMap { surfaceId -> AgentHQEntry? in
                guard let paneId = workspace.rootPane.paneId(containing: surfaceId),
                      let surface = workspace.rootPane.surface(id: surfaceId) else {
                    return nil
                }

                let gitState = gitStatesBySurfaceId[surfaceId]
                return AgentHQEntry(
                    workspaceId: workspace.id,
                    workspaceName: workspace.name,
                    paneId: paneId,
                    surfaceId: surfaceId,
                    title: surface.title,
                    agentType: surface.agentType,
                    status: activityStatus(for: surface),
                    branchName: gitState?.branchName,
                    isLinkedWorktree: gitState?.isLinkedWorktree ?? false,
                    progress: progressBySurfaceId[surfaceId],
                    lastActivity: surface.lastActivity,
                    summary: sessionSummariesBySurfaceId[surfaceId],
                    pendingCompletionSequence: surface.pendingCompletionSequence
                )
            }
        }

        return AgentHQEntry.sorted(entries)
    }
}
