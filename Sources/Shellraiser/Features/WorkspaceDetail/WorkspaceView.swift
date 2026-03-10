import SwiftUI

/// Focus trigger logic extracted from `WorkspaceView` for unit testing.
enum WorkspaceViewFocusLogic {
    /// Returns whether the current selection should restore focus for this workspace.
    static func shouldRequestFocus(selectedWorkspaceId: UUID?, workspaceId: UUID) -> Bool {
        selectedWorkspaceId == workspaceId
    }

    /// Returns whether a first-appearance layout refresh should trigger a follow-up focus restore.
    static func shouldRestoreFocusAfterLayoutRefresh(pendingRestore: Bool) -> Bool {
        pendingRestore
    }
}

/// Main detail view for a selected workspace.
struct WorkspaceView: View {
    let workspaceId: UUID
    @ObservedObject var manager: WorkspaceManager
    @State private var runtimeAppearanceRefreshTick = 0
    @State private var hasPerformedInitialLayoutRefresh = false
    @State private var pendingFocusRestoreAfterLayoutRefresh = false

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
            pendingFocusRestoreAfterLayoutRefresh = WorkspaceViewFocusLogic.shouldRequestFocus(
                selectedWorkspaceId: manager.window.selectedWorkspaceId,
                workspaceId: workspaceId
            )

            DispatchQueue.main.async {
                runtimeAppearanceRefreshTick &+= 1
            }
        }
        .onChange(of: manager.window.selectedWorkspaceId, initial: true) { _, selectedWorkspaceId in
            guard WorkspaceViewFocusLogic.shouldRequestFocus(
                selectedWorkspaceId: selectedWorkspaceId,
                workspaceId: workspaceId
            ) else {
                return
            }
            requestTerminalFocusIfSelected()
        }
        .onChange(of: runtimeAppearanceRefreshTick) { _, _ in
            guard WorkspaceViewFocusLogic.shouldRestoreFocusAfterLayoutRefresh(
                pendingRestore: pendingFocusRestoreAfterLayoutRefresh
            ) else {
                return
            }
            pendingFocusRestoreAfterLayoutRefresh = false
            requestTerminalFocusIfSelected()
        }
    }

    /// Returns the full pane tree, passing zoom state down to collapse non-zoomed branches.
    @ViewBuilder
    private func displayedPaneNode(for workspace: WorkspaceModel) -> some View {
        PaneNodeView(
            workspaceId: workspace.id,
            node: workspace.rootPane,
            zoomedPaneId: workspace.zoomedPaneId,
            manager: manager
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Re-requests terminal first-responder focus once the selected workspace view is mounted.
    private func requestTerminalFocusIfSelected() {
        guard WorkspaceViewFocusLogic.shouldRequestFocus(
            selectedWorkspaceId: manager.window.selectedWorkspaceId,
            workspaceId: workspaceId
        ) else {
            return
        }

        DispatchQueue.main.async {
            manager.restoreSelectedWorkspaceTerminalFocus()
        }
    }
}
