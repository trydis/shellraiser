import Foundation

/// Owns pane/surface operations and focused-surface bookkeeping.
final class WorkspaceSurfaceManager {
    /// Applies an in-place mutation to a workspace.
    func mutateWorkspace(
        id: UUID,
        workspaces: inout [WorkspaceModel],
        transform: (inout WorkspaceModel) -> Void
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        transform(&workspaces[index])
    }

    /// Clears stale zoom state when the targeted pane no longer exists.
    func normalizeZoomedPane(in workspace: inout WorkspaceModel) {
        guard let zoomedPaneId = workspace.zoomedPaneId else { return }
        if !workspace.rootPane.containsPane(zoomedPaneId) {
            workspace.zoomedPaneId = nil
        }
    }
}
