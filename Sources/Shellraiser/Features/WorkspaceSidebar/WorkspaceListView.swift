import SwiftUI

/// Sidebar list for selecting and managing workspaces.
struct WorkspaceListView: View {
    @ObservedObject var manager: WorkspaceManager

    @State private var showingNewWorkspaceSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceSection
        }
        .padding(.horizontal, 6)
        .padding(.top, 48)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            NewWorkspaceSheet { name in
                _ = manager.createWorkspace(name: name)
            }
            .presentationBackground(.clear)
        }
    }

    /// Scrollable section containing selectable workspace cards.
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        WorkspaceSidebarRow(
                            workspace: workspace,
                            displayIndex: index + 1,
                            isSelected: manager.window.selectedWorkspaceId == workspace.id,
                            focusedBranchName: manager.focusedBranchName(workspaceId: workspace.id),
                            pendingCount: manager.pendingCompletionCount(workspaceId: workspace.id),
                            onSelect: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    manager.selectWorkspace(workspace.id)
                                }
                            },
                            onRename: {
                                manager.requestRenameWorkspace(id: workspace.id)
                            },
                            onDelete: {
                                manager.requestDeleteWorkspace(id: workspace.id)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
