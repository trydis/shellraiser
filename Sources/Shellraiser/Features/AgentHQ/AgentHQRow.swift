import SwiftUI

/// Row chrome for one Agent HQ session entry.
struct AgentHQRow: View {
    let entry: AgentHQEntry
    let isSelected: Bool
    let onActivate: () -> Void
    let onRename: () -> Void
    let onClose: () -> Void
    let onDismissCompletion: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .top, spacing: 14) {
                statusBadge

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let progress = entry.progress?.progress {
                            Text("\(progress)%")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    metadataRow

                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                statusChip
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.highlight.opacity(0.3) : AppTheme.stroke.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuContent
        }
    }

    /// Row-scoped actions: jump, rename, dismiss pending completion, and close.
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onActivate()
        } label: {
            Label("Jump to Session", systemImage: "arrow.right.circle")
        }

        Button {
            onRename()
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        if entry.status == .ready {
            Button {
                onDismissCompletion()
            } label: {
                Label("Dismiss", systemImage: "checkmark.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            onClose()
        } label: {
            Label("Close Session", systemImage: "xmark.circle")
        }
    }

    /// Compact status icon shown at the leading edge of the row.
    private var statusBadge: some View {
        Image(systemName: entry.status.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(entry.status.tintColor)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
    }

    /// Workspace, agent, branch, and worktree metadata line.
    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(entry.workspaceName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(AppTheme.textSecondary)

            metadataSeparator

            Text(entry.agentType.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            if let branchName = entry.branchName {
                metadataSeparator

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                    Text(branchName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(AppTheme.highlight)
            }

            if entry.isLinkedWorktree {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.highlight)
            }
        }
    }

    /// Small dot separator used between metadata fragments.
    private var metadataSeparator: some View {
        Text("·")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
    }

    /// Status label chip shown at the trailing edge of the row.
    private var statusChip: some View {
        Text(entry.status.displayName.uppercased())
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(entry.status.tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(entry.status.tintColor.opacity(0.14))
            )
    }
}
