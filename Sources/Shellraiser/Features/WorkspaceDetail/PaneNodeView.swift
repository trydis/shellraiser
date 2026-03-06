import SwiftUI

/// Recursive renderer for split and leaf nodes in the workspace pane tree.
struct PaneNodeView: View {
    let workspaceId: UUID
    let node: PaneNodeModel
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        Group {
            switch node {
            case .leaf(let leaf):
                PaneLeafView(workspaceId: workspaceId, leaf: leaf, manager: manager)
            case .split(let split):
                PaneSplitView(workspaceId: workspaceId, split: split, manager: manager)
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
