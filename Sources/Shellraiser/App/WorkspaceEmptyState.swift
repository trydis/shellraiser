import SwiftUI

/// Empty-state presentation for the detail panel when no workspace is selected.
struct WorkspaceEmptyState: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Shellraiser")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)

            Text("A terminal workspace that feels composed, not assembled. Split panes, track pending completions, and keep multiple agent sessions readable at a glance.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: 560, alignment: .leading)

            HStack(spacing: 10) {
                StatPill(title: "Workspaces", value: "\(manager.workspaces.count)")
                StatPill(title: "Pending", value: "\(manager.workspaces.reduce(0) { $0 + manager.pendingCompletionCount(workspaceId: $1.id) })", emphasized: manager.hasPendingCompletions)
            }

            Button {
                _ = manager.createWorkspace(name: "Workspace")
            } label: {
                Label("Create Workspace", systemImage: "plus")
            }
            .buttonStyle(AccentButtonStyle())
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
