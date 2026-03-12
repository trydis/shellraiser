import Foundation

/// Owns workspace-level lifecycle operations (load, select, create, rename, delete).
final class WorkspaceCatalogManager {
    /// Returns the currently selected workspace if any.
    func selectedWorkspace(from workspaces: [WorkspaceModel], window: WindowModel) -> WorkspaceModel? {
        guard let id = window.selectedWorkspaceId else { return nil }
        return workspace(id: id, in: workspaces)
    }

    /// Finds a workspace by identifier.
    func workspace(id: UUID, in workspaces: [WorkspaceModel]) -> WorkspaceModel? {
        workspaces.first(where: { $0.id == id })
    }

    /// Loads persisted workspaces and initializes selection.
    func loadWorkspaces(
        into workspaces: inout [WorkspaceModel],
        window: inout WindowModel,
        persistence: any WorkspacePersisting
    ) {
        workspaces = persistence.load() ?? []

        if workspaces.isEmpty {
            _ = createWorkspace(
                name: "Workspace",
                workspaces: &workspaces,
                window: &window,
                persistence: persistence
            )
            return
        }

        var didRepairState = false
        for index in workspaces.indices {
            if synchronizeFocusedSurface(workspace: &workspaces[index]) {
                didRepairState = true
            }
        }

        if didRepairState {
            persistence.save(workspaces)
        }

        if window.selectedWorkspaceId == nil {
            window.selectedWorkspaceId = workspaces.first?.id
        }
    }

    /// Creates a workspace and selects it.
    @discardableResult
    func createWorkspace(
        name: String = "New Workspace",
        initialSurface: SurfaceModel = SurfaceModel.makeDefault(),
        rootWorkingDirectory: String? = nil,
        workspaces: inout [WorkspaceModel],
        window: inout WindowModel,
        persistence: any WorkspacePersisting
    ) -> WorkspaceModel {
        let workspace = WorkspaceModel.makeDefault(
            name: name,
            initialSurface: initialSurface,
            rootWorkingDirectory: rootWorkingDirectory
        )
        workspaces.append(workspace)
        window.selectedWorkspaceId = workspace.id
        persistence.save(workspaces)
        return workspace
    }

    /// Renames an existing workspace.
    func renameWorkspace(
        id: UUID,
        name: String,
        workspaces: inout [WorkspaceModel],
        persistence: any WorkspacePersisting
    ) {
        mutateWorkspace(id: id, workspaces: &workspaces) { workspace in
            let isOnlyWhitespace = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            workspace.name = isOnlyWhitespace ? workspace.name : name
        }
        persistence.save(workspaces)
    }

    /// Deletes a workspace and adjusts current selection.
    func deleteWorkspace(
        id: UUID,
        workspaces: inout [WorkspaceModel],
        window: inout WindowModel,
        persistence: any WorkspacePersisting
    ) {
        workspaces.removeAll { $0.id == id }

        if window.selectedWorkspaceId == id {
            window.selectedWorkspaceId = workspaces.first?.id
        }

        if workspaces.isEmpty {
            _ = createWorkspace(
                name: "Workspace",
                workspaces: &workspaces,
                window: &window,
                persistence: persistence
            )
        } else {
            persistence.save(workspaces)
        }
    }

    /// Selects a workspace in the current window.
    func selectWorkspace(
        _ id: UUID?,
        window: inout WindowModel,
        workspaces: inout [WorkspaceModel],
        persistence: any WorkspacePersisting
    ) {
        window.selectedWorkspaceId = id

        guard let id else { return }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        if synchronizeFocusedSurface(workspace: &workspaces[index]) {
            persistence.save(workspaces)
        }
    }

    /// Finds the first unread idle notification and focuses it.
    func focusFirstUnreadNotification(
        workspaces: inout [WorkspaceModel],
        window: inout WindowModel,
        persistence: any WorkspacePersisting
    ) {
        for index in workspaces.indices {
            if let surfaceId = workspaces[index].rootPane.firstUnreadSurfaceId() {
                window.selectedWorkspaceId = workspaces[index].id
                workspaces[index].focusedSurfaceId = surfaceId
                _ = synchronizeFocusedSurface(workspace: &workspaces[index])
                persistence.save(workspaces)
                return
            }
        }
    }

    /// Aligns focused surface id with pane active selection state.
    @discardableResult
    private func synchronizeFocusedSurface(workspace: inout WorkspaceModel) -> Bool {
        let originalRootPane = workspace.rootPane
        let originalFocusedSurfaceId = workspace.focusedSurfaceId

        if let focusedSurfaceId = workspace.focusedSurfaceId,
           workspace.rootPane.activateSurface(surfaceId: focusedSurfaceId) != nil {
            return workspace.rootPane != originalRootPane || workspace.focusedSurfaceId != originalFocusedSurfaceId
        }

        let fallbackSurfaceId = workspace.rootPane.firstActiveSurfaceId()
        workspace.focusedSurfaceId = fallbackSurfaceId

        if let fallbackSurfaceId {
            _ = workspace.rootPane.activateSurface(surfaceId: fallbackSurfaceId)
        }

        return workspace.rootPane != originalRootPane || workspace.focusedSurfaceId != originalFocusedSurfaceId
    }

    /// Applies an in-place mutation to a workspace.
    private func mutateWorkspace(
        id: UUID,
        workspaces: inout [WorkspaceModel],
        transform: (inout WorkspaceModel) -> Void
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        transform(&workspaces[index])
    }
}
