import Foundation

/// Orientation used when a pane is split into two child panes.
enum SplitOrientation: String, Codable, CaseIterable {
    case horizontal
    case vertical
}

/// Leaf node in the pane tree; owns a tab strip of surfaces.
struct PaneLeafModel: Identifiable, Codable, Equatable {
    var id: UUID
    var surfaces: [SurfaceModel]
    var activeSurfaceId: UUID?

    /// Creates an empty leaf pane.
    static func empty() -> PaneLeafModel {
        PaneLeafModel(id: UUID(), surfaces: [], activeSurfaceId: nil)
    }
}

/// Split node in the pane tree with two children.
struct PaneSplitModel: Identifiable, Codable, Equatable {
    var id: UUID
    var orientation: SplitOrientation
    var ratio: Double
    var first: PaneNodeModel
    var second: PaneNodeModel
}

/// Recursive pane tree used by each workspace.
indirect enum PaneNodeModel: Identifiable, Codable, Equatable {
    case leaf(PaneLeafModel)
    case split(PaneSplitModel)

    /// Stable identifier for the current node.
    var id: UUID {
        switch self {
        case .leaf(let leaf):
            return leaf.id
        case .split(let split):
            return split.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case leaf
        case split
    }

    private enum NodeType: String, Codable {
        case leaf
        case split
    }

    /// Decodes pane tree nodes using a tagged union strategy.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)

        switch type {
        case .leaf:
            self = .leaf(try container.decode(PaneLeafModel.self, forKey: .leaf))
        case .split:
            self = .split(try container.decode(PaneSplitModel.self, forKey: .split))
        }
    }

    /// Encodes pane tree nodes using a tagged union strategy.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .leaf(let leaf):
            try container.encode(NodeType.leaf, forKey: .type)
            try container.encode(leaf, forKey: .leaf)
        case .split(let split):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(split, forKey: .split)
        }
    }

    /// Creates a default tree with one pane and one surface.
    static func initialTree() -> PaneNodeModel {
        let surface = SurfaceModel.makeDefault()
        let leaf = PaneLeafModel(id: UUID(), surfaces: [surface], activeSurfaceId: surface.id)
        return .leaf(leaf)
    }
}
