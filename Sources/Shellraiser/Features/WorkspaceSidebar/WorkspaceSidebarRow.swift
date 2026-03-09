import SwiftUI

/// Selectable workspace card used in the sidebar.
struct WorkspaceSidebarRow: View {
    let workspace: WorkspaceModel
    let displayIndex: Int
    let isSelected: Bool
    let focusedGitState: ResolvedGitState?
    let pendingCount: Int
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    /// Number of tabs in the workspace used for compact metadata.
    private var surfaceCount: Int {
        workspace.rootPane.allSurfaceIds().count
    }

    /// Number of panes rendered in the workspace tree.
    private var paneCount: Int {
        paneCount(for: workspace.rootPane)
    }

    /// Returns whether the row should render a dedicated Git metadata line.
    private var showsGitMetadata: Bool {
        focusedGitState?.hasVisibleMetadata ?? false
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(displayIndex)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.82) : AppTheme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textPrimary.opacity(0.92))
                        .lineLimit(1)

                    if showsGitMetadata {
                        gitMetadataRow
                    }

                    HStack(spacing: 8) {
                        StatPill(title: "P", value: "\(paneCount)")
                        StatPill(title: "T", value: "\(surfaceCount)")
                        if pendingCount > 0 {
                            StatPill(title: "Q", value: "\(pendingCount)", emphasized: true)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.085) : Color.white.opacity(0.022))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.highlight.opacity(0.28) : AppTheme.stroke.opacity(0.85), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(AppTheme.accentGradient)
                    .frame(width: isSelected ? 3 : 0)
                    .padding(.vertical, 10)
                    .opacity(isSelected ? 1 : 0)
            }
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0.05), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Rename") {
                onRename()
            }

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    /// Counts leaf panes recursively for compact workspace metadata.
    private func paneCount(for node: PaneNodeModel) -> Int {
        switch node {
        case .leaf:
            return 1
        case .split(let split):
            return paneCount(for: split.first) + paneCount(for: split.second)
        }
    }

    /// Renders the focused surface's Git metadata above the structural stat chips.
    private var gitMetadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let branchName = focusedGitState?.branchName {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.highlight)

                    Text(branchName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if focusedGitState?.isLinkedWorktree == true {
                WorktreeChip()
            }

            Spacer(minLength: 0)
        }
    }
}

/// Compact linked-worktree indicator shown beside the focused branch metadata.
private struct WorktreeChip: View {
    var body: some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.highlight)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppTheme.stroke, lineWidth: 1)
            )
            .accessibilityLabel("Linked worktree")
    }
}
