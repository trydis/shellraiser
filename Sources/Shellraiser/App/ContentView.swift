import SwiftUI

/// Root window view with workspace sidebar and detail panel.
struct ContentView: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        NavigationSplitView {
            WorkspaceListView(manager: manager)
                .navigationSplitViewColumnWidth(min: 276, ideal: 292)
                .ignoresSafeArea(.container, edges: .top)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            AppBackdrop()
        }
        .onAppear {
            manager.loadWorkspaces()
        }
        .sheet(isPresented: $manager.isCommandPalettePresented) {
            CommandPaletteSheet(manager: manager)
        }
        .sheet(
            isPresented: pendingWorkspaceRenameIsPresented,
            onDismiss: {
                manager.cancelPendingWorkspaceRename()
            }
        ) {
            if let request = manager.pendingWorkspaceRename {
                RenameWorkspaceSheet(name: request.currentName) { newName in
                    manager.confirmPendingWorkspaceRename(name: newName)
                }
                .presentationBackground(.clear)
            }
        }
        .alert(
            "Delete Workspace?",
            isPresented: pendingWorkspaceDeletionIsPresented,
            presenting: manager.pendingWorkspaceDeletion
        ) { _ in
            Button("Cancel", role: .cancel) {
                manager.cancelPendingWorkspaceDeletion()
            }

            Button("Delete Workspace", role: .destructive) {
                manager.confirmPendingWorkspaceDeletion()
            }
        } message: { request in
            Text(
                "\(request.workspaceName) has \(request.activeProcessCount) active terminal\(request.activeProcessCount == 1 ? "" : "s"). Deleting it will close those processes."
            )
        }
    }

    /// Alert binding used for destructive workspace deletion confirmation.
    private var pendingWorkspaceDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { manager.pendingWorkspaceDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    manager.cancelPendingWorkspaceDeletion()
                }
            }
        )
    }

    /// Sheet binding used for shared workspace rename presentation.
    private var pendingWorkspaceRenameIsPresented: Binding<Bool> {
        Binding(
            get: { manager.pendingWorkspaceRename != nil },
            set: { isPresented in
                if !isPresented {
                    manager.cancelPendingWorkspaceRename()
                }
            }
        )
    }

    /// Selects the workspace detail UI or the empty state when nothing is chosen.
    @ViewBuilder
    private var detailContent: some View {
        if let workspaceId = manager.window.selectedWorkspaceId {
            ZStack {
                ForEach(manager.workspaces) { workspace in
                    WorkspaceView(workspaceId: workspace.id, manager: manager)
                        .opacity(workspace.id == workspaceId ? 1 : 0)
                        .allowsHitTesting(workspace.id == workspaceId)
                        .accessibilityHidden(workspace.id != workspaceId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: .top)
        } else {
            WorkspaceEmptyState(manager: manager)
        }
    }
}
