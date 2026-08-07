import Foundation

/// Builds the flattened, globally-sorted cross-workspace session list for Agent HQ.
extension WorkspaceManager {
    /// Toggles presentation of the Agent HQ dashboard overlay, refreshing summaries on open.
    func toggleAgentHQ() {
        isAgentHQPresented.toggle()
        if isAgentHQPresented {
            refreshAllAgentHQSummaries()
        }
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

    /// Refreshes cached last-activity summaries for every currently live surface.
    ///
    /// Called when Agent HQ opens so newly visible rows show fresh text immediately, without
    /// waiting for the next activity event. Reads happen off the main actor inside
    /// `SessionSummaryService`; each surface refresh is independent and non-debounced here since
    /// the overlay is opening on demand rather than reacting to a burst of events.
    func refreshAllAgentHQSummaries() {
        for workspace in workspaces {
            for surfaceId in workspace.rootPane.allSurfaceIds() {
                refreshSessionSummary(workspaceId: workspace.id, surfaceId: surfaceId, debounced: false)
            }
        }
    }

    /// Refreshes the cached last-activity summary for a single surface.
    ///
    /// Cancels any in-flight refresh for the same surface before spawning a replacement, mirroring
    /// `refreshGitBranch`. Debounced by default so a burst of activity events (started/completed
    /// in quick succession) coalesces into a single transcript read.
    @discardableResult
    func refreshSessionSummary(workspaceId: UUID, surfaceId: UUID, debounced: Bool = true) -> Task<Void, Never> {
        sessionSummaryTasks[surfaceId]?.cancel()

        guard let workspace = workspace(id: workspaceId),
              let surface = surface(in: workspace.rootPane, surfaceId: surfaceId) else {
            let task = Task<Void, Never> {}
            sessionSummaryTasks[surfaceId] = task
            return task
        }

        let request = SessionSummaryRequest(
            agentType: surface.agentType,
            sessionId: surface.sessionId,
            transcriptPath: surface.transcriptPath
        )
        let service = sessionSummaryService
        let debounceNanoseconds: UInt64 = debounced ? 400_000_000 : 0

        let task = Task.detached(priority: .utility) { [weak self] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            let summary = await service.refreshSummary(surfaceId: surfaceId, request: request)
            guard !Task.isCancelled, let summary else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                self.sessionSummariesBySurfaceId[surfaceId] = summary
            }
        }

        sessionSummaryTasks[surfaceId] = task
        return task
    }

    /// Removes cached summary state for a surface that is no longer present.
    func clearSessionSummary(surfaceId: UUID) {
        sessionSummaryTasks[surfaceId]?.cancel()
        sessionSummaryTasks.removeValue(forKey: surfaceId)
        sessionSummariesBySurfaceId.removeValue(forKey: surfaceId)

        let service = sessionSummaryService
        Task.detached(priority: .utility) {
            await service.clearCache(surfaceId: surfaceId)
        }
    }
}
