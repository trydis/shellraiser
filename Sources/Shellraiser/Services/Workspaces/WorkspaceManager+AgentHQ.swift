import Foundation

/// Builds the flattened, globally-sorted cross-workspace session list for Agent HQ.
extension WorkspaceManager {
    /// Toggles presentation of the Agent HQ dashboard overlay.
    func toggleAgentHQ() {
        isAgentHQPresented.toggle()
    }

    /// Dismisses the Agent HQ dashboard overlay if it is open.
    func dismissAgentHQ() {
        isAgentHQPresented = false
    }

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

    /// Jumps to an Agent HQ entry's surface, mirroring the `Cmd+Shift+U` completion jump.
    func activateAgentHQEntry(_ entry: AgentHQEntry) {
        focusCompletionSurface(entry.surfaceId)
    }

    /// Renames an Agent HQ entry's surface tab title.
    func renameAgentHQEntry(_ entry: AgentHQEntry, title: String) {
        setSurfaceTitle(workspaceId: entry.workspaceId, surfaceId: entry.surfaceId, title: title)
    }

    /// Closes an Agent HQ entry's surface, confirming first when the agent is still running.
    func closeAgentHQEntry(_ entry: AgentHQEntry) {
        if entry.status == .running {
            let request = SurfaceCloseRequest(
                workspaceId: entry.workspaceId,
                paneId: entry.paneId,
                surfaceId: entry.surfaceId,
                surfaceTitle: entry.title
            )
            guard confirmSurfaceClose(request) else { return }
        }

        closeSurface(workspaceId: entry.workspaceId, paneId: entry.paneId, surfaceId: entry.surfaceId)
    }

    /// Dismisses a pending completion for an Agent HQ entry without jumping to it.
    func dismissAgentHQEntryCompletion(_ entry: AgentHQEntry) {
        surfaceManager.clearPendingCompletion(
            workspaceId: entry.workspaceId,
            surfaceId: entry.surfaceId,
            workspaces: &workspaces,
            persistence: persistence
        )
        completionNotifications.removeNotifications(for: entry.surfaceId)
        updateDockBadge()
    }
}
