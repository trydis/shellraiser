import SwiftUI

/// Selectable workspace card used in the sidebar.
struct WorkspaceSidebarRow: View {
    let workspace: WorkspaceModel
    let displayIndex: Int
    let isSelected: Bool
    let focusedGitState: ResolvedGitState?
    let isWorking: Bool
    let pendingCount: Int
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    /// Returns whether the row should render a dedicated Git metadata line.
    private var showsGitMetadata: Bool {
        focusedGitState?.hasVisibleMetadata ?? false
    }

    /// Returns whether the row should render a dedicated status line.
    private var showsStatusRow: Bool {
        pendingCount > 0
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                WorkspaceIndexBadge(
                    displayIndex: displayIndex,
                    isSelected: isSelected,
                    isWorking: isWorking
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textPrimary.opacity(0.92))
                        .lineLimit(1)

                    if showsGitMetadata {
                        gitMetadataRow
                    }

                    if showsStatusRow {
                        statusRow
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

    /// Renders the focused surface's Git metadata above the optional status indicators.
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

    /// Renders workspace-level working and pending-completion indicators.
    private var statusRow: some View {
        HStack(spacing: 10) {
            if pendingCount > 0 {
                WorkspacePendingIndicator()
            }

            Spacer(minLength: 0)
        }
    }
}

/// Leading workspace badge that shows either the static circle or the working indicator.
private struct WorkspaceIndexBadge: View {
    let displayIndex: Int
    let isSelected: Bool
    let isWorking: Bool

    /// Foreground color used for the badge number.
    private var numberColor: Color {
        if isWorking {
            return AppTheme.textPrimary
        }

        if isSelected {
            return Color.black.opacity(0.82)
        }

        return AppTheme.textSecondary
    }

    /// Background treatment used for the badge footprint.
    private var badgeBackground: some View {
        Circle()
            .fill(backgroundStyle)
    }

    /// Fill style for the badge background.
    private var backgroundStyle: AnyShapeStyle {
        if isWorking {
            return AnyShapeStyle(Color.clear)
        }

        if isSelected {
            return AnyShapeStyle(AppTheme.accentGradient)
        }

        return AnyShapeStyle(Color.white.opacity(0.08))
    }

    var body: some View {
        ZStack {
            badgeBackground

            if isWorking {
                WorkspaceWorkingIndicator()
            }

            Text("\(displayIndex)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(numberColor)
        }
        .frame(width: 20, height: 20)
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

/// Animated progress indicator shown while a workspace has an active agent turn.
private struct WorkspaceWorkingIndicator: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppTheme.highlight)
                .frame(width: 20, height: 20)
                .clipped()
                .symbolEffect(
                    .rotate.byLayer,
                    options: .repeat(.continuous)
                )
                .accessibilityLabel("Workspace is working")
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppTheme.highlight)
                .frame(width: 20, height: 20)
                .clipped()
                .accessibilityLabel("Workspace is working")
        }
    }
}

/// Animated bell shown while a workspace owns queued completions.
private struct WorkspacePendingIndicator: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)
                .symbolEffect(.bounce.up.byLayer, options: .repeat(.continuous))
                .accessibilityLabel("Workspace has pending completions")
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)
                .accessibilityLabel("Workspace has pending completions")
        }
    }
}
