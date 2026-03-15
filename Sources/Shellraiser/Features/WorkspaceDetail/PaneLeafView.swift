import SwiftUI

/// Renderer for leaf panes with tab strip and terminal surface body.
struct PaneLeafView: View {
    let workspaceId: UUID
    let leaf: PaneLeafModel
    @ObservedObject var manager: WorkspaceManager

    /// Active in-terminal search state, set by the runtime when a search starts or ends.
    @State private var searchState: SurfaceSearchState?

    /// Active surface for the pane.
    private var activeSurface: SurfaceModel? {
        if let activeId = leaf.activeSurfaceId {
            return leaf.surfaces.first(where: { $0.id == activeId })
        }
        return leaf.surfaces.first
    }

    /// Workspace snapshot used to resolve focused split state.
    private var workspace: WorkspaceModel? {
        manager.workspace(id: workspaceId)
    }

    /// Whether this leaf represents the currently focused pane.
    private var isFocusedPane: Bool {
        guard let focusedSurfaceId = workspace?.focusedSurfaceId else { return true }
        return activeSurface?.id == focusedSurfaceId
    }

    /// Whether dimming should be rendered over this pane.
    private var shouldDimUnfocusedPane: Bool {
        guard let workspace else { return false }
        guard workspace.rootPane.containsSplit else { return false }
        return !isFocusedPane
    }

    /// Styling sourced from Ghostty runtime configuration.
    private var unfocusedSplitStyle: GhosttyRuntime.UnfocusedSplitStyle {
        GhosttyRuntime.shared.unfocusedSplitStyle()
    }

    /// Pane chrome styling sourced from Ghostty configuration.
    private var chromeStyle: GhosttyRuntime.ChromeStyle {
        GhosttyRuntime.shared.chromeStyle()
    }

    /// Queue highlight state for this pane in the current workspace.
    private var completionHighlightState: CompletionPaneHighlightState {
        manager.completionHighlightState(workspaceId: workspaceId, paneId: leaf.id)
    }

    /// Border color derived from queued completion priority.
    private var paneBorderColor: Color {
        switch completionHighlightState {
        case .none:
            return isFocusedPane ? AppTheme.highlight.opacity(0.32) : AppTheme.stroke
        case .recentHold:
            return AppTheme.highlight
        case .recentFade:
            return AppTheme.highlight.opacity(0.55)
        case .queued:
            return AppTheme.highlight.opacity(0.75)
        case .current:
            return AppTheme.highlight
        }
    }

    /// Border width derived from queued completion priority.
    private var paneBorderWidth: CGFloat {
        switch completionHighlightState {
        case .none:
            return isFocusedPane ? 1.4 : 1
        case .recentHold:
            return 3
        case .recentFade:
            return 2
        case .queued:
            return 2
        case .current:
            return 3
        }
    }

    /// Current queue position metadata for this pane, when pending.
    private var queuePosition: (position: Int, total: Int)? {
        manager.pendingCompletionQueuePosition(workspaceId: workspaceId, paneId: leaf.id)
    }

    /// Additional opacity used for transient handled-highlight fadeout.
    private var paneBorderOpacity: Double {
        switch completionHighlightState {
        case .none:
            return 1
        case .recentHold:
            return 1
        case .recentFade:
            return 0.45
        case .queued:
            return 0.78
        case .current:
            return 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            panelBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: chromeStyle.backgroundColor).opacity(0.94),
                            Color(nsColor: chromeStyle.backgroundColor).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(paneBorderColor, lineWidth: paneBorderWidth)
                .opacity(paneBorderOpacity)
        )
        .shadow(color: .black.opacity(isFocusedPane ? 0.24 : 0.12), radius: 24, x: 0, y: 18)
        .overlay(alignment: .topTrailing) {
            if let queuePosition {
                Text("\(queuePosition.position)/\(queuePosition.total)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.accentGradient))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            paneContextMenu
        }
        .animation(.easeOut(duration: 1.2), value: completionHighlightState)
    }

    /// Renders the surface tabs for the pane.
    private var tabStrip: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(leaf.surfaces) { surface in
                        SurfaceTabButton(
                            surface: surface,
                            workspaceId: workspaceId,
                            paneId: leaf.id,
                            manager: manager,
                            isSelected: surface.id == activeSurface?.id,
                            chromeStyle: chromeStyle,
                            onSelect: {
                                manager.activateSurface(workspaceId: workspaceId, paneId: leaf.id, surfaceId: surface.id)
                            },
                            onClose: {
                                manager.closeSurface(workspaceId: workspaceId, paneId: leaf.id, surfaceId: surface.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.045), Color.white.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.stroke)
                .frame(height: 1)
        }
    }

    /// Renders the currently active terminal surface.
    private var panelBody: some View {
        ZStack {
            Group {
                if let activeSurface {
                    GhosttyTerminalView(
                        surface: activeSurface,
                        config: activeSurface.terminalConfig,
                        isFocused: isFocusedPane,
                        onActivate: {
                            manager.activateSurface(workspaceId: workspaceId, paneId: leaf.id, surfaceId: activeSurface.id)
                        },
                        onIdleNotification: {
                            // Agent completion notifications are driven by managed
                            // Claude/Codex hooks so queue timing matches actual turns.
                        },
                        onInput: { input in
                            manager.handleSurfaceInput(
                                workspaceId: workspaceId,
                                surfaceId: activeSurface.id,
                                input: input
                            )
                        },
                        onTitleChange: { title in
                            manager.setSurfaceTitle(workspaceId: workspaceId, surfaceId: activeSurface.id, title: title)
                        },
                        onWorkingDirectoryChange: { workingDirectory in
                            manager.setSurfaceWorkingDirectory(
                                workspaceId: workspaceId,
                                surfaceId: activeSurface.id,
                                workingDirectory: workingDirectory
                            )
                        },
                        onChildExited: {
                            manager.handleSurfaceChildExit(
                                workspaceId: workspaceId,
                                surfaceId: activeSurface.id
                            )
                        },
                        onPaneNavigationRequest: { direction in
                            manager.focusAdjacentPane(from: activeSurface.id, direction: direction)
                        },
                        onSearchStateChange: { state in
                            searchState = state
                        }
                    )
                    .id(activeSurface.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                } else {
                    ContentUnavailableView("No Surfaces", systemImage: "terminal")
                }
            }

            if shouldDimUnfocusedPane && unfocusedSplitStyle.overlayOpacity > 0 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: unfocusedSplitStyle.fillColor))
                    .opacity(unfocusedSplitStyle.overlayOpacity)
                    .padding(8)
                    .allowsHitTesting(false)
            }

            if let searchState {
                TerminalSearchOverlay(
                    searchState: searchState,
                    onNavigateNext: {
                        guard let surfaceId = activeSurface?.id else { return }
                        GhosttyRuntime.shared.performBindingAction(
                            surfaceId: surfaceId,
                            action: "navigate_search:next"
                        )
                    },
                    onNavigatePrevious: {
                        guard let surfaceId = activeSurface?.id else { return }
                        GhosttyRuntime.shared.performBindingAction(
                            surfaceId: surfaceId,
                            action: "navigate_search:previous"
                        )
                    },
                    onClose: {
                        guard let surfaceId = activeSurface?.id else { return }
                        GhosttyRuntime.shared.endSearch(surfaceId: surfaceId)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Context menu for pane-scoped actions.
    @ViewBuilder
    private var paneContextMenu: some View {
        Button {
            _ = manager.performPaneCommand(.newSurface, workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("New Surface", systemImage: "plus")
        }
        .disabled(!manager.canPerformPaneCommand(.newSurface, workspaceId: workspaceId, paneId: leaf.id))

        Button {
            _ = manager.performPaneCommand(.split(.horizontal), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Split Horizontally", systemImage: "rectangle.split.2x1")
        }
        .disabled(!manager.canPerformPaneCommand(.split(.horizontal), workspaceId: workspaceId, paneId: leaf.id))

        Button {
            _ = manager.performPaneCommand(.split(.vertical), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Split Vertically", systemImage: "rectangle.split.1x2")
        }
        .disabled(!manager.canPerformPaneCommand(.split(.vertical), workspaceId: workspaceId, paneId: leaf.id))

        Divider()

        Button {
            _ = manager.performPaneCommand(.toggleZoom, workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Toggle Split Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .disabled(!manager.canPerformPaneCommand(.toggleZoom, workspaceId: workspaceId, paneId: leaf.id))

        Divider()

        Button {
            _ = manager.performPaneCommand(.focus(.left), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Focus Left Pane", systemImage: "arrow.left")
        }
        .disabled(!manager.canPerformPaneCommand(.focus(.left), workspaceId: workspaceId, paneId: leaf.id))

        Button {
            _ = manager.performPaneCommand(.focus(.right), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Focus Right Pane", systemImage: "arrow.right")
        }
        .disabled(!manager.canPerformPaneCommand(.focus(.right), workspaceId: workspaceId, paneId: leaf.id))

        Button {
            _ = manager.performPaneCommand(.focus(.up), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Focus Up Pane", systemImage: "arrow.up")
        }
        .disabled(!manager.canPerformPaneCommand(.focus(.up), workspaceId: workspaceId, paneId: leaf.id))

        Button {
            _ = manager.performPaneCommand(.focus(.down), workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label("Focus Down Pane", systemImage: "arrow.down")
        }
        .disabled(!manager.canPerformPaneCommand(.focus(.down), workspaceId: workspaceId, paneId: leaf.id))

        Divider()

        Button(role: leaf.surfaces.count > 1 ? nil : .destructive) {
            _ = manager.performPaneCommand(.closeActiveItem, workspaceId: workspaceId, paneId: leaf.id)
        } label: {
            Label(
                manager.closeItemTitle(workspaceId: workspaceId, paneId: leaf.id),
                systemImage: "xmark"
            )
        }
        .disabled(!manager.canPerformPaneCommand(.closeActiveItem, workspaceId: workspaceId, paneId: leaf.id))
    }
}
