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
        if let selectedWorkspace {
            applyControlEnvironment(for: selectedWorkspace)
        }
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
        let workspace = workspaceCatalog.createWorkspace(
            name: name,
            initialSurface: initialSurface,
            workspaces: &workspaces,
            window: &window,
            persistence: persistence
        )
        applyControlEnvironment(for: workspace)
        return workspace
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
        clearBusySurfaces(releasedSurfaceIds)
        clearLiveCodexSessionSurfaces(releasedSurfaceIds)
        releasedSurfaceIds.forEach {
            completionNotifications.removeNotifications(for: $0)
            GhosttyRuntime.shared.releaseSurface(surfaceId: $0)
            clearGitBranch(surfaceId: $0)
        }
        if let selectedWorkspace {
            applyControlEnvironment(for: selectedWorkspace)
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

        let request = WorkspaceDeletionRequest(
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            activeProcessCount: activeProcessCount
        )

        guard confirmWorkspaceDeletion(request) else { return }
        deleteWorkspace(id: workspace.id)
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

    /// Freezes resume invalidation so active agent sessions remain resumable across app shutdown.
    func prepareForTermination() {
        guard !isTerminating else { return }
        isTerminating = true
        save()
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

/// Injects stable control-environment variables for Shellraiser-managed terminal surfaces.
extension WorkspaceManager {
    /// Applies `FUX_*` environment variables to the active surface in a newly created workspace.
    func applyControlEnvironment(for workspace: WorkspaceModel) {
        guard let surfaceId = workspace.rootPane.firstActiveSurfaceId(),
              let paneId = workspace.rootPane.paneId(containing: surfaceId) else {
            return
        }

        applyControlEnvironment(workspaceId: workspace.id, paneId: paneId, surfaceId: surfaceId)
    }

    /// Applies `FUX_*` environment variables to one surface by resolving its current pane.
    func applyControlEnvironment(workspaceId: UUID, surfaceId: UUID) {
        guard let workspace = workspace(id: workspaceId),
              let paneId = workspace.rootPane.paneId(containing: surfaceId) else {
            return
        }

        applyControlEnvironment(workspaceId: workspaceId, paneId: paneId, surfaceId: surfaceId)
    }

    /// Applies `FUX_*` environment variables to one surface in a known workspace/pane context.
    func applyControlEnvironment(workspaceId: UUID, paneId: UUID, surfaceId: UUID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            return
        }

        let environment = controlEnvironment(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId
        )
        let didUpdate = workspaces[workspaceIndex].rootPane.updateEnvironment(
            for: surfaceId,
            environment: environment
        )

        if didUpdate {
            persistence.save(workspaces)
        }
    }

    /// Returns the stable `FUX_*` environment block for one surface context.
    func controlEnvironment(
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID
    ) -> [String: String] {
        [
            "FUX_CONTROL_MODE": "native",
            "FUX_WORKSPACE_ID": workspaceId.uuidString.lowercased(),
            "FUX_PANE_ID": paneId.uuidString.lowercased(),
            "FUX_SURFACE_ID": surfaceId.uuidString.lowercased()
        ]
    }
}

/// Pane-tree environment mutation helpers used by Shellraiser control-tagging flows.
private extension PaneNodeModel {
    /// Updates one surface environment dictionary in place.
    mutating func updateEnvironment(
        for surfaceId: UUID,
        environment: [String: String]
    ) -> Bool {
        switch self {
        case .leaf(var leaf):
            guard let index = leaf.surfaces.firstIndex(where: { $0.id == surfaceId }) else {
                return false
            }

            for (key, value) in environment {
                leaf.surfaces[index].terminalConfig.environment[key] = value
            }
            self = .leaf(leaf)
            return true
        case .split(var split):
            if split.first.updateEnvironment(for: surfaceId, environment: environment) {
                self = .split(split)
                return true
            }

            if split.second.updateEnvironment(for: surfaceId, environment: environment) {
                self = .split(split)
                return true
            }

            return false
        }
    }
}
