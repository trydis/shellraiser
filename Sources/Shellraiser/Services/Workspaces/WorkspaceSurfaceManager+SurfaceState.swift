import Foundation

extension WorkspaceSurfaceManager {
    /// Updates idle state for a surface and tracks unread idle notifications.
    func setIdleState(
        workspaceId: UUID,
        surfaceId: UUID,
        isIdle: Bool,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        var shouldPersist = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                let wasIdle = surface.isIdle
                if wasIdle != isIdle {
                    surface.isIdle = isIdle
                    shouldPersist = true
                }
                surface.lastActivity = Date()

                if isIdle && !wasIdle {
                    surface.hasUnreadIdleNotification = true
                    shouldPersist = true
                }
            }
        }

        if shouldPersist {
            persistence.save(workspaces)
        }
    }

    /// Records a newly completed agent response for a surface and assigns FIFO order.
    @discardableResult
    func markPendingCompletion(
        workspaceId: UUID,
        surfaceId: UUID,
        agentType: AgentType,
        sequence: Int,
        timestamp: Date,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) -> Bool {
        var shouldPersist = false
        var didEnqueue = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                if surface.agentType != agentType {
                    surface.agentType = agentType
                    shouldPersist = true
                }

                surface.lastActivity = timestamp
                surface.lastCompletionAt = timestamp

                if surface.hasPendingCompletion {
                    surface.hasUnreadIdleNotification = true
                    shouldPersist = true
                    return
                }

                surface.isIdle = true
                surface.hasUnreadIdleNotification = true
                surface.hasPendingCompletion = true
                surface.pendingCompletionSequence = sequence
                shouldPersist = true
                didEnqueue = true
            }
        }

        if shouldPersist {
            persistence.save(workspaces)
        }

        return didEnqueue
    }

    /// Clears completion state once a queued pane has been handled by the user.
    @discardableResult
    func clearPendingCompletion(
        workspaceId: UUID,
        surfaceId: UUID,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) -> Bool {
        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                guard surface.hasPendingCompletion || surface.hasUnreadIdleNotification || surface.isIdle else {
                    return
                }

                surface.isIdle = false
                surface.hasUnreadIdleNotification = false
                surface.hasPendingCompletion = false
                surface.pendingCompletionSequence = nil
                didChange = true
            }
        }

        if didChange {
            persistence.save(workspaces)
        }

        return didChange
    }

    /// Updates the agent type associated with a surface after a managed wrapper emits an event.
    func setAgentType(
        workspaceId: UUID,
        surfaceId: UUID,
        agentType: AgentType,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                guard surface.agentType != agentType else { return }
                surface.agentType = agentType
                didChange = true
            }
        }

        if didChange {
            persistence.save(workspaces)
        }
    }

    /// Clears unread notification state on a focused surface.
    func clearUnreadNotification(
        workspaceId: UUID,
        surfaceId: UUID,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                surface.hasUnreadIdleNotification = false
            }
        }
        persistence.save(workspaces)
    }

    /// Updates the visible tab title using the terminal-provided title.
    func setSurfaceTitle(
        workspaceId: UUID,
        surfaceId: UUID,
        title: String,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "~" : title
        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                guard surface.title != resolvedTitle else { return }
                surface.title = resolvedTitle
                didChange = true
            }
        }

        if didChange {
            persistence.save(workspaces)
        }
    }

    /// Updates the reported working directory for a surface when the terminal changes directories.
    func setSurfaceWorkingDirectory(
        workspaceId: UUID,
        surfaceId: UUID,
        workingDirectory: String,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        let normalizedWorkingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWorkingDirectory.isEmpty else { return }

        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                guard surface.terminalConfig.workingDirectory != normalizedWorkingDirectory else { return }
                surface.terminalConfig.workingDirectory = normalizedWorkingDirectory
                didChange = true
            }
        }

        if didChange {
            persistence.save(workspaces)
        }
    }
}
