import Foundation

extension WorkspaceSurfaceManager {
    /// Adds a surface to the target pane leaf.
    func addSurface(
        workspaceId: UUID,
        paneId: UUID,
        surface: SurfaceModel,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) -> Bool {
        var appended = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            appended = workspace.rootPane.appendSurface(to: paneId, surface: surface)
            if appended {
                workspace.focusedSurfaceId = surface.id
            }
        }
        persistence.save(workspaces)
        return appended
    }

    /// Closes a surface from a target pane leaf.
    func closeSurface(
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            let removed = workspace.rootPane.removeSurface(from: paneId, surfaceId: surfaceId)
            guard removed else { return }

            _ = workspace.rootPane.compactEmptyLeaves()
            if workspace.focusedSurfaceId == surfaceId {
                workspace.focusedSurfaceId = workspace.rootPane.firstActiveSurfaceId()
            }
            normalizeZoomedPane(in: &workspace)
        }
        persistence.save(workspaces)
    }

    /// Marks a surface as active in both pane and workspace focus state.
    func activateSurface(
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            let activated = workspace.rootPane.setActiveSurface(in: paneId, surfaceId: surfaceId)
            if activated {
                workspace.focusedSurfaceId = surfaceId
            }
        }
        persistence.save(workspaces)
    }

    /// Splits a leaf pane and creates a fresh terminal in the new pane.
    func splitPane(
        workspaceId: UUID,
        paneId: UUID,
        orientation: SplitOrientation,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) -> UUID? {
        var createdSurfaceId: UUID?

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            if let newSurfaceId = workspace.rootPane.splitLeaf(paneId: paneId, orientation: orientation) {
                workspace.focusedSurfaceId = newSurfaceId
                createdSurfaceId = newSurfaceId
            }
            normalizeZoomedPane(in: &workspace)
        }
        persistence.save(workspaces)
        return createdSurfaceId
    }

    /// Updates a split ratio. Use `persist: false` during drag updates.
    func updateSplitRatio(
        workspaceId: UUID,
        paneId: UUID,
        ratio: Double,
        persist: Bool,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            _ = workspace.rootPane.updateSplitRatio(paneId: paneId, ratio: ratio)
        }

        if persist {
            persistence.save(workspaces)
        }
    }

    /// Toggles zoom for a target pane within the workspace split tree.
    func togglePaneZoom(
        workspaceId: UUID,
        paneId: UUID,
        workspaces: inout [WorkspaceModel],
        persistence: WorkspacePersistence
    ) {
        var didChange = false

        mutateWorkspace(id: workspaceId, workspaces: &workspaces) { workspace in
            guard workspace.rootPane.containsPane(paneId) else { return }

            if workspace.zoomedPaneId == paneId {
                workspace.zoomedPaneId = nil
            } else {
                workspace.zoomedPaneId = paneId
            }
            didChange = true
        }

        if didChange {
            persistence.save(workspaces)
        }
    }
}
