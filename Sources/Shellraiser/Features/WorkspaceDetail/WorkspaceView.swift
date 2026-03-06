import SwiftUI

/// Main detail view for a selected workspace.
struct WorkspaceView: View {
    let workspaceId: UUID
    @ObservedObject var manager: WorkspaceManager
    @State private var runtimeAppearanceRefreshTick = 0
    @State private var hasPerformedInitialLayoutRefresh = false

    private var workspace: WorkspaceModel? {
        manager.workspace(id: workspaceId)
    }

    var body: some View {
        Group {
            if let workspace {
                displayedPaneNode(for: workspace)
                    .id(runtimeAppearanceRefreshTick)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            } else {
                ContentUnavailableView("Workspace Missing", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: GhosttyRuntime.appearanceDidChangeNotification)) { _ in
            runtimeAppearanceRefreshTick &+= 1
        }
        .onAppear {
            guard !hasPerformedInitialLayoutRefresh else { return }
            hasPerformedInitialLayoutRefresh = true

            DispatchQueue.main.async {
                runtimeAppearanceRefreshTick &+= 1
            }
        }
    }

    /// Returns the tree node that should be rendered for the current zoom state.
    @ViewBuilder
    private func displayedPaneNode(for workspace: WorkspaceModel) -> some View {
        let node = workspace.zoomedPaneId.flatMap { workspace.rootPane.paneNode(id: $0) } ?? workspace.rootPane
        PaneNodeView(
            workspaceId: workspace.id,
            node: node,
            manager: manager
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
