import SwiftUI

/// Recursive renderer for split and leaf nodes in the workspace pane tree.
struct PaneNodeView: View {
    let workspaceId: UUID
    let node: PaneNodeModel
    /// When set, only this pane leaf is given visible space; all siblings are collapsed to zero.
    let zoomedPaneId: UUID?
    @ObservedObject var manager: WorkspaceManager

    init(workspaceId: UUID, node: PaneNodeModel, zoomedPaneId: UUID? = nil, manager: WorkspaceManager) {
        self.workspaceId = workspaceId
        self.node = node
        self.zoomedPaneId = zoomedPaneId
        self.manager = manager
    }

    var body: some View {
        Group {
            switch node {
            case .leaf(let leaf):
                PaneLeafView(workspaceId: workspaceId, leaf: leaf, manager: manager)
            case .split(let split):
                PaneSplitView(workspaceId: workspaceId, split: split, zoomedPaneId: zoomedPaneId, manager: manager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PaneNodeModel {
    /// Returns true when the pane tree contains at least one split node.
    var containsSplit: Bool {
        switch self {
        case .leaf:
            return false
        case .split:
            return true
        }
    }
}
