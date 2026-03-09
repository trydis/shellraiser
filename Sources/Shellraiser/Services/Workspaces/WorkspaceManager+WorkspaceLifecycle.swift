import Foundation

/// Workspace lifecycle and selection flows for the shared manager.
extension WorkspaceManager {
    /// Returns the currently selected workspace if any.
    var selectedWorkspace: WorkspaceModel? {
        workspaceCatalog.selectedWorkspace(from: workspaces, window: window)
    }

    /// Loads persisted workspaces and initializes selection.
    func loadWorkspaces() {
        guard !hasLoadedPersistedWorkspaces else { return }

        workspaceCatalog.loadWorkspaces(
            into: &workspaces,
            window: &window,
            persistence: persistence
        )
        synchronizePendingCompletionCursor()
        refreshFocusedWorkspaceGitBranches()
        hasLoadedPersistedWorkspaces = true
    }

    /// Finds a workspace by identifier.
    func workspace(id: UUID) -> WorkspaceModel? {
        workspaceCatalog.workspace(id: id, in: workspaces)
    }

    /// Creates a workspace and selects it.
    @discardableResult
    func createWorkspace(
        name: String = "New Workspace",
        initialSurface: SurfaceModel = SurfaceModel.makeDefault()
    ) -> WorkspaceModel {
        workspaceCatalog.createWorkspace(
            name: name,
            initialSurface: initialSurface,
            workspaces: &workspaces,
            window: &window,
            persistence: persistence
        )
    }

    /// Renames an existing workspace.
    func renameWorkspace(id: UUID, name: String) {
        workspaceCatalog.renameWorkspace(
            id: id,
            name: name,
            workspaces: &workspaces,
            persistence: persistence
        )
    }

    /// Deletes a workspace and adjusts current selection.
    func deleteWorkspace(id: UUID) {
        let releasedSurfaceIds = workspace(id: id)?.rootPane.allSurfaceIds() ?? []
        workspaceCatalog.deleteWorkspace(
            id: id,
            workspaces: &workspaces,
            window: &window,
            persistence: persistence
        )
        releasedSurfaceIds.forEach {
            completionNotifications.removeNotifications(for: $0)
            GhosttyRuntime.shared.releaseSurface(surfaceId: $0)
            clearGitBranch(surfaceId: $0)
        }
    }

    /// Requests deletion for a workspace and asks for confirmation when live terminals exist.
    func requestDeleteWorkspace(id: UUID) {
        guard let workspace = workspace(id: id) else { return }

        let activeProcessCount = activeProcessCount(in: workspace)
        guard activeProcessCount > 0 else {
            deleteWorkspace(id: id)
            return
        }

        pendingWorkspaceDeletion = WorkspaceDeletionRequest(
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            activeProcessCount: activeProcessCount
        )
    }

    /// Requests deletion for the currently selected workspace.
    func requestDeleteSelectedWorkspace() {
        guard let workspaceId = window.selectedWorkspaceId else { return }
        requestDeleteWorkspace(id: workspaceId)
    }

    /// Requests rename for a workspace using the shared rename sheet.
    func requestRenameWorkspace(id: UUID) {
        guard let workspace = workspace(id: id) else { return }

        pendingWorkspaceRename = WorkspaceRenameRequest(
            workspaceId: workspace.id,
            currentName: workspace.name
        )
    }

    /// Requests rename for the currently selected workspace.
    func requestRenameSelectedWorkspace() {
        guard let workspaceId = window.selectedWorkspaceId else { return }
        requestRenameWorkspace(id: workspaceId)
    }

    /// Confirms the currently pending workspace rename request.
    func confirmPendingWorkspaceRename(name: String) {
        guard let request = pendingWorkspaceRename else { return }
        pendingWorkspaceRename = nil
        renameWorkspace(id: request.workspaceId, name: name)
    }

    /// Cancels the currently pending workspace rename request.
    func cancelPendingWorkspaceRename() {
        pendingWorkspaceRename = nil
    }

    /// Confirms the currently pending workspace deletion request.
    func confirmPendingWorkspaceDeletion() {
        guard let request = pendingWorkspaceDeletion else { return }
        pendingWorkspaceDeletion = nil
        deleteWorkspace(id: request.workspaceId)
    }

    /// Cancels the currently pending workspace deletion request.
    func cancelPendingWorkspaceDeletion() {
        pendingWorkspaceDeletion = nil
    }

    /// Selects a workspace in the current window.
    func selectWorkspace(_ id: UUID?) {
        workspaceCatalog.selectWorkspace(
            id,
            window: &window,
            workspaces: &workspaces,
            persistence: persistence
        )
    }

    /// Persists the current workspace collection.
    func save() {
        persistence.save(workspaces)
    }

    /// Selects workspace by 1-based index in sidebar order.
    func selectWorkspace(atDisplayIndex index: Int) {
        guard index > 0, index <= workspaces.count else { return }
        selectWorkspace(workspaces[index - 1].id)
    }

    /// Returns whether a workspace exists at the provided 1-based index.
    func hasWorkspace(atDisplayIndex index: Int) -> Bool {
        index > 0 && index <= workspaces.count
    }

    /// Restores first-responder focus to the selected workspace's active terminal surface.
    func restoreSelectedWorkspaceTerminalFocus() {
        guard let workspaceId = window.selectedWorkspaceId,
              let workspace = workspace(id: workspaceId) else {
            return
        }

        guard let surfaceId = workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId() else {
            return
        }

        GhosttyRuntime.shared.focusSurfaceHost(surfaceId: surfaceId)
    }

    /// Returns the number of live terminal child processes currently mounted in a workspace.
    private func activeProcessCount(in workspace: WorkspaceModel) -> Int {
        workspace.rootPane.allSurfaceIds().count
    }
}
