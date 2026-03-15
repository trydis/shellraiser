import SwiftUI

/// Tab button for a single terminal surface entry.
struct SurfaceTabButton: View {
    let surface: SurfaceModel
    let workspaceId: UUID
    let paneId: UUID
    @ObservedObject var manager: WorkspaceManager
    let isSelected: Bool
    let chromeStyle: GhosttyRuntime.ChromeStyle
    let onSelect: () -> Void
    let onClose: () -> Void

    /// Selected tab background derived from configured foreground color.
    private var selectedBackgroundColor: Color {
        Color(nsColor: chromeStyle.foregroundColor).opacity(0.18)
    }

    /// Tab title foreground color derived from configured terminal foreground.
    private var titleForegroundColor: Color {
        Color(nsColor: chromeStyle.foregroundColor).opacity(isSelected ? 1 : 0.82)
    }

    /// Close button foreground color with lower prominence on inactive tabs.
    private var closeButtonForegroundColor: Color {
        Color(nsColor: chromeStyle.foregroundColor).opacity(isSelected ? 0.76 : 0.55)
    }

    /// Color for the tab status dot derived from progress state, completion, or default.
    private var dotFill: AnyShapeStyle {
        if let report = manager.progressBySurfaceId[surface.id] {
            return AnyShapeStyle(report.state.tintColor)
        }
        if surface.hasPendingCompletion { return AnyShapeStyle(AppTheme.accentGradient) }
        return AnyShapeStyle(Color.white.opacity(0.2))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotFill)
                        .frame(width: 6, height: 6)

                    Text(surface.title)
                        .lineLimit(1)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleForegroundColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(selectedBackgroundColor) : AnyShapeStyle(Color.white.opacity(0.03)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? AppTheme.stroke.opacity(1.2) : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select surface \(surface.title)")
            .accessibilityHint("Activates this tab")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(closeButtonForegroundColor)
            .accessibilityLabel("Close surface \(surface.title)")
            .accessibilityHint("Closes this tab")
        }
        .contextMenu {
            tabContextMenu
        }
    }

    /// Context menu for tab-scoped actions.
    @ViewBuilder
    private var tabContextMenu: some View {
        Button {
            onSelect()
        } label: {
            Label("Activate Tab", systemImage: "checkmark.circle")
        }
        .disabled(isSelected)

        Button {
            _ = manager.performPaneCommand(.newSurface, workspaceId: workspaceId, paneId: paneId)
        } label: {
            Label("New Surface", systemImage: "plus")
        }
        .disabled(!manager.canPerformPaneCommand(.newSurface, workspaceId: workspaceId, paneId: paneId))

        Divider()

        Button {
            _ = manager.performPaneCommand(.nextSurface, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)
        } label: {
            Label("Next Tab In Pane", systemImage: "chevron.right")
        }
        .disabled(!manager.canPerformPaneCommand(.nextSurface, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id))

        Button {
            _ = manager.performPaneCommand(.previousSurface, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)
        } label: {
            Label("Previous Tab In Pane", systemImage: "chevron.left")
        }
        .disabled(!manager.canPerformPaneCommand(.previousSurface, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id))

        Divider()

        Button(role: .destructive) {
            _ = manager.performPaneCommand(.closeActiveItem, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)
        } label: {
            Label(
                manager.closeItemTitle(workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id),
                systemImage: "xmark"
            )
        }
        .disabled(!manager.canPerformPaneCommand(.closeActiveItem, workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id))
    }
}
