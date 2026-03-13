import Foundation

extension WorkspaceSurfaceManager {
    /// Persists the resolved agent runtime and session identifier for a surface.
    func setSessionIdentity(
        workspaceId: UUID,
        surfaceId: UUID,
        agentType: AgentType,
        sessionId: String,
        transcriptPath: String? = nil,
        workspaces: inout [WorkspaceModel],
        persistence: any WorkspacePersisting
    ) {
        let normalizedSessionId = normalizedSessionId(for: agentType, sessionId: sessionId)
        guard !normalizedSessionId.isEmpty else { return }
        let resolvedTranscriptPath: String?
        if let transcriptPath {
            resolvedTranscriptPath = normalizedTranscriptPath(for: agentType, transcriptPath: transcriptPath)
        } else {
            resolvedTranscriptPath = nil
        }

        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                if surface.agentType != agentType {
                    surface.agentType = agentType
                    didChange = true
                }

                if surface.sessionId != normalizedSessionId {
                    surface.sessionId = normalizedSessionId
                    didChange = true
                }

                switch agentType {
                case .claudeCode:
                    if let resolvedTranscriptPath,
                       surface.transcriptPath != resolvedTranscriptPath {
                        surface.transcriptPath = resolvedTranscriptPath
                        didChange = true
                    }
                case .codex:
                    if !surface.transcriptPath.isEmpty {
                        surface.transcriptPath = ""
                        didChange = true
                    }
                }

                if !surface.shouldResumeSession {
                    surface.shouldResumeSession = true
                    didChange = true
                }
            }
        }

        if didChange {
            persistence.save(workspaces)
        }
    }

    /// Normalizes stored session identifiers so resume commands use a stable persisted value.
    private func normalizedSessionId(for agentType: AgentType, sessionId: String) -> String {
        let trimmedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionId.isEmpty else { return "" }

        switch agentType {
        case .claudeCode:
            return trimmedSessionId.lowercased()
        case .codex:
            return trimmedSessionId
        }
    }

    /// Normalizes persisted transcript locations used to validate Claude resume availability.
    private func normalizedTranscriptPath(for agentType: AgentType, transcriptPath: String) -> String {
        let trimmedTranscriptPath = transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscriptPath.isEmpty else { return "" }

        switch agentType {
        case .claudeCode:
            return trimmedTranscriptPath
        case .codex:
            return ""
        }
    }

    /// Updates whether a surface should attempt session resume on the next launch.
    func setResumeEligibility(
        workspaceId: UUID,
        surfaceId: UUID,
        shouldResumeSession: Bool,
        workspaces: inout [WorkspaceModel],
        persistence: any WorkspacePersisting
    ) {
        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.mutateSurface(surfaceId: surfaceId) { surface in
                guard surface.shouldResumeSession != shouldResumeSession else { return }
                surface.shouldResumeSession = shouldResumeSession
                didChange = true
            }
        }

        if didChange {
            persistence.save(workspaces)
        }
    }

    /// Updates idle state for a surface and tracks unread idle notifications.
    func setIdleState(
        workspaceId: UUID,
        surfaceId: UUID,
        isIdle: Bool,
        workspaces: inout [WorkspaceModel],
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
        persistence: any WorkspacePersisting
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
