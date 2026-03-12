import Foundation

/// Workspace entry listed in the sidebar.
struct WorkspaceModel: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var rootPane: PaneNodeModel
    var focusedSurfaceId: UUID?
    var zoomedPaneId: UUID?
    var rootWorkingDirectory: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootPane
        case focusedSurfaceId
        case zoomedPaneId
        case rootWorkingDirectory
    }

    /// Creates a fully specified workspace entry.
    init(
        id: UUID,
        name: String,
        rootPane: PaneNodeModel,
        focusedSurfaceId: UUID?,
        zoomedPaneId: UUID?,
        rootWorkingDirectory: String = NSHomeDirectory()
    ) {
        self.id = id
        self.name = name
        self.rootPane = rootPane
        self.focusedSurfaceId = focusedSurfaceId
        self.zoomedPaneId = zoomedPaneId
        self.rootWorkingDirectory = rootWorkingDirectory
    }

    /// Decodes persisted workspaces while defaulting the stable workspace root for older payloads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rootPane = try container.decode(PaneNodeModel.self, forKey: .rootPane)
        focusedSurfaceId = try container.decodeIfPresent(UUID.self, forKey: .focusedSurfaceId)
        zoomedPaneId = try container.decodeIfPresent(UUID.self, forKey: .zoomedPaneId)
        rootWorkingDirectory = try container.decodeIfPresent(String.self, forKey: .rootWorkingDirectory)
            ?? rootPane.firstWorkspaceWorkingDirectory()
            ?? NSHomeDirectory()
    }

    /// Encodes persisted workspaces with an explicit stable workspace root path.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(rootPane, forKey: .rootPane)
        try container.encodeIfPresent(focusedSurfaceId, forKey: .focusedSurfaceId)
        try container.encodeIfPresent(zoomedPaneId, forKey: .zoomedPaneId)
        try container.encode(rootWorkingDirectory, forKey: .rootWorkingDirectory)
    }

    /// Creates a new workspace with one starter pane and surface.
    static func makeDefault(
        name: String = "New Workspace",
        initialSurface: SurfaceModel = SurfaceModel.makeDefault(),
        rootWorkingDirectory: String? = nil
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
            zoomedPaneId: nil,
            rootWorkingDirectory: rootWorkingDirectory ?? initialSurface.terminalConfig.workingDirectory
        )
    }
}

private extension PaneNodeModel {
    /// Returns the first terminal working directory captured in the pane tree.
    func firstWorkspaceWorkingDirectory() -> String? {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.first?.terminalConfig.workingDirectory
        case .split(let split):
            return split.first.firstWorkspaceWorkingDirectory() ?? split.second.firstWorkspaceWorkingDirectory()
        }
    }
}
