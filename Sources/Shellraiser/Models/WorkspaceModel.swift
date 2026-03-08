import Foundation

/// Workspace entry listed in the sidebar.
struct WorkspaceModel: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var rootPane: PaneNodeModel
    var focusedSurfaceId: UUID?
    var zoomedPaneId: UUID?

    /// Creates a new workspace with one starter pane and surface.
    static func makeDefault(
        name: String = "New Workspace",
        initialSurface: SurfaceModel = SurfaceModel.makeDefault()
    ) -> WorkspaceModel {
        let tree = PaneNodeModel.initialTree(surface: initialSurface)

        var focusedSurfaceId: UUID?
        if case .leaf(let leaf) = tree {
            focusedSurfaceId = leaf.activeSurfaceId
        }

        return WorkspaceModel(
            id: UUID(),
            name: name,
            rootPane: tree,
            focusedSurfaceId: focusedSurfaceId,
            zoomedPaneId: nil
        )
    }
}
