import AppKit
import Foundation

/// Pane, surface, and Ghostty command flows for the shared manager.
extension WorkspaceManager {
    /// Handles a terminal child-process exit by closing the surface unless app shutdown is in progress.
    func handleSurfaceChildExit(workspaceId: UUID, surfaceId: UUID) {
        guard !isTerminating else { return }
        guard let workspace = workspace(id: workspaceId),
              let paneId = workspace.rootPane.paneId(containing: surfaceId) else {
            return
        }

        closeSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: surfaceId)
    }

    /// Adds a surface to the target pane leaf.
    func addSurface(workspaceId: UUID, paneId: UUID, surface: SurfaceModel) {
        let appended = surfaceManager.addSurface(
            workspaceId: workspaceId,
            paneId: paneId,
            surface: surface,
            workspaces: &workspaces,
            persistence: persistence
        )
        if appended {
            GhosttyRuntime.shared.focusSurfaceHost(surfaceId: surface.id)
        }
    }

    /// Closes a surface from a target pane leaf.
    func closeSurface(workspaceId: UUID, paneId: UUID, surfaceId: UUID) {
        surfaceManager.closeSurface(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId,
            workspaces: &workspaces,
            persistence: persistence
        )
        completionNotifications.removeNotifications(for: surfaceId)
        GhosttyRuntime.shared.releaseSurface(surfaceId: surfaceId)
        clearBusySurface(surfaceId)
        clearLiveCodexSessionSurface(surfaceId)
        clearGitBranch(surfaceId: surfaceId)

        if let workspace = workspace(id: workspaceId),
           let focusedSurfaceId = workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId(),
           let focusedSurface = surface(in: workspace.rootPane, surfaceId: focusedSurfaceId) {
            refreshGitBranch(
                workspaceId: workspaceId,
                surfaceId: focusedSurfaceId,
                workingDirectory: focusedSurface.terminalConfig.workingDirectory
            )
        }
    }

    /// Marks a surface as active in both pane and workspace focus state.
    func activateSurface(workspaceId: UUID, paneId: UUID, surfaceId: UUID) {
        surfaceManager.activateSurface(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId,
            workspaces: &workspaces,
            persistence: persistence
        )
        let didHandleCompletion = surfaceManager.clearPendingCompletion(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            workspaces: &workspaces,
            persistence: persistence
        )
        if didHandleCompletion {
            markRecentlyHandled(surfaceId: surfaceId)
        }
        completionNotifications.removeNotifications(for: surfaceId)
        GhosttyRuntime.shared.focusSurfaceHost(surfaceId: surfaceId)

        if let workspace = workspace(id: workspaceId),
           let surface = surface(in: workspace.rootPane, surfaceId: surfaceId) {
            refreshGitBranch(
                workspaceId: workspaceId,
                surfaceId: surfaceId,
                workingDirectory: surface.terminalConfig.workingDirectory
            )
        }
    }

    /// Splits a leaf pane and creates a fresh terminal in the new pane.
    func splitPane(
        workspaceId: UUID,
        paneId: UUID,
        orientation: SplitOrientation,
        position: SplitChildPosition = .second
    ) {
        if let surfaceId = surfaceManager.splitPane(
            workspaceId: workspaceId,
            paneId: paneId,
            orientation: orientation,
            position: position,
            newSurface: configuredDefaultSurface(),
            workspaces: &workspaces,
            persistence: persistence
        ) {
            GhosttyRuntime.shared.focusSurfaceHost(surfaceId: surfaceId)
        }
    }

    /// Updates persisted split ratio. Use `persist: false` during drag updates.
    func updateSplitRatio(workspaceId: UUID, paneId: UUID, ratio: Double, persist: Bool = true) {
        surfaceManager.updateSplitRatio(
            workspaceId: workspaceId,
            paneId: paneId,
            ratio: ratio,
            persist: persist,
            workspaces: &workspaces,
            persistence: persistence
        )
    }

    /// Records terminal activity and marks gated Codex submit events as busy.
    func handleSurfaceInput(workspaceId: UUID, surfaceId: UUID, input: SurfaceInputEvent) {
        surfaceManager.setIdleState(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            isIdle: false,
            workspaces: &workspaces,
            persistence: persistence
        )

        guard let workspace = workspace(id: workspaceId),
              let surface = surface(in: workspace.rootPane, surfaceId: surfaceId),
              surface.agentType == .codex else {
            return
        }

        guard input.isSubmit else { return }
        guard liveCodexSessionSurfaceIds.contains(surfaceId) else { return }

        markSurfaceBusy(surfaceId)
    }

    /// Updates tab title using the current terminal title.
    func setSurfaceTitle(workspaceId: UUID, surfaceId: UUID, title: String) {
        surfaceManager.setSurfaceTitle(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            title: title,
            workspaces: &workspaces,
            persistence: persistence
        )
    }

    /// Updates the tracked working directory for a surface and refreshes its Git branch state.
    @discardableResult
    func setSurfaceWorkingDirectory(workspaceId: UUID, surfaceId: UUID, workingDirectory: String) -> Task<Void, Never>? {
        let normalizedWorkingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        surfaceManager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            workingDirectory: normalizedWorkingDirectory,
            workspaces: &workspaces,
            persistence: persistence
        )
        guard !normalizedWorkingDirectory.isEmpty else { return nil }
        return refreshGitBranch(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            workingDirectory: normalizedWorkingDirectory
        )
    }

    /// Creates a surface in the currently focused pane of the selected workspace.
    func createSurfaceInFocusedPane() {
        guard let context = focusedPaneContext() else { return }
        addSurface(
            workspaceId: context.workspaceId,
            paneId: context.paneId,
            surface: configuredDefaultSurface()
        )
    }

    /// Returns whether an app-owned focused-pane command is currently supported.
    func canPerformFocusedPaneCommand(_ command: FocusedPaneCommand) -> Bool {
        guard let context = focusedPaneContext() else { return false }
        return canPerformPaneCommand(command, context: context)
    }

    /// Executes an app-owned focused-pane command when supported.
    @discardableResult
    func performFocusedPaneCommand(_ command: FocusedPaneCommand) -> Bool {
        guard let context = focusedPaneContext() else { return false }
        return performPaneCommand(command, context: context)
    }

    /// Returns whether a pane command is supported for a specific target pane.
    func canPerformPaneCommand(
        _ command: FocusedPaneCommand,
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID? = nil
    ) -> Bool {
        guard let context = paneCommandContext(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId
        ) else {
            return false
        }

        return canPerformPaneCommand(command, context: context)
    }

    /// Executes a pane command for a specific target pane or tab.
    @discardableResult
    func performPaneCommand(
        _ command: FocusedPaneCommand,
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID? = nil
    ) -> Bool {
        guard let context = paneCommandContext(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId
        ) else {
            return false
        }

        return performPaneCommand(command, context: context)
    }

    /// Splits the currently focused pane in the selected workspace.
    func splitFocusedPane(orientation: SplitOrientation) {
        guard let context = focusedPaneContext() else { return }
        splitPane(workspaceId: context.workspaceId, paneId: context.paneId, orientation: orientation)
    }

    /// Closes the currently focused surface in the selected workspace.
    func closeFocusedSurface() {
        guard let workspaceId = window.selectedWorkspaceId else { return }
        guard let workspace = self.workspace(id: workspaceId) else { return }

        let surfaceId = focusedSurfaceId() ?? workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId()
        guard let surfaceId else { return }
        guard let paneId = workspace.rootPane.paneId(containing: surfaceId) else { return }
        closeSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: surfaceId)
    }

    /// Moves tab focus to the next surface in the focused pane.
    func focusNextSurfaceInPane() {
        focusAdjacentSurfaceInPane(step: 1)
    }

    /// Moves tab focus to the previous surface in the focused pane.
    func focusPreviousSurfaceInPane() {
        focusAdjacentSurfaceInPane(step: -1)
    }

    /// Moves pane focus in the provided direction relative to the focused pane.
    func focusAdjacentPane(direction: PaneNodeModel.PaneFocusDirection) {
        if let sourceSurfaceId = currentResponderSurfaceId() {
            focusAdjacentPane(from: sourceSurfaceId, direction: direction)
            return
        }

        guard let workspaceId = window.selectedWorkspaceId else { return }
        guard let workspace = self.workspace(id: workspaceId) else { return }

        let sourcePaneId = focusedPaneId(in: workspace) ?? workspace.rootPane.firstLeafId()
        guard let sourcePaneId else { return }

        guard let targetPaneId = workspace.rootPane.adjacentPaneId(from: sourcePaneId, direction: direction) else {
            return
        }

        guard let targetSurfaceId = workspace.rootPane.activeSurfaceId(in: targetPaneId) else {
            return
        }

        activateSurface(workspaceId: workspaceId, paneId: targetPaneId, surfaceId: targetSurfaceId)
    }

    /// Moves pane focus in the provided direction relative to a specific surface.
    func focusAdjacentPane(from sourceSurfaceId: UUID, direction: PaneNodeModel.PaneFocusDirection) {
        guard let workspaceId = window.selectedWorkspaceId else { return }
        guard let workspace = self.workspace(id: workspaceId) else { return }

        let sourcePaneId = workspace.rootPane.paneId(containing: sourceSurfaceId) ?? focusedPaneId(in: workspace)
        guard let sourcePaneId else { return }

        guard let targetPaneId = workspace.rootPane.adjacentPaneId(from: sourcePaneId, direction: direction) else {
            return
        }

        guard let targetSurfaceId = workspace.rootPane.activeSurfaceId(in: targetPaneId) else {
            return
        }

        activateSurface(workspaceId: workspaceId, paneId: targetPaneId, surfaceId: targetSurfaceId)
    }

    /// Returns whether a workspace is currently selected.
    var hasSelectedWorkspace: Bool {
        window.selectedWorkspaceId != nil
    }

    /// Returns whether a terminal surface is available for focused binding actions.
    var hasFocusedSurface: Bool {
        focusedSurfaceId() != nil
    }

    /// Returns the current menu title for the focused close action.
    var closeFocusedItemTitle: String {
        guard let context = focusedPaneContext() else {
            return "Close Active Pane/Tab"
        }

        return closeItemTitle(for: context)
    }

    /// Returns the current menu title for a specific pane or tab close action.
    func closeItemTitle(workspaceId: UUID, paneId: UUID, surfaceId: UUID? = nil) -> String {
        guard let context = paneCommandContext(
            workspaceId: workspaceId,
            paneId: paneId,
            surfaceId: surfaceId
        ) else {
            return "Close Active Pane/Tab"
        }

        return closeItemTitle(for: context)
    }

    /// Runs a named Ghostty binding action against the focused surface.
    @discardableResult
    func performFocusedSurfaceBindingAction(_ action: String) -> Bool {
        guard let surfaceId = focusedSurfaceId() else { return false }
        return GhosttyRuntime.shared.performBindingAction(surfaceId: surfaceId, action: action)
    }

    /// Returns whether the focused pane is currently zoomed.
    var isFocusedPaneZoomed: Bool {
        guard let workspaceId = window.selectedWorkspaceId,
              let workspace = self.workspace(id: workspaceId),
              let paneId = focusedPaneId(in: workspace) else {
            return false
        }

        return workspace.zoomedPaneId == paneId
    }

    /// Toggles app-level zoom for the currently focused pane.
    func toggleFocusedPaneZoom() {
        guard let context = focusedPaneContext() else { return }

        surfaceManager.togglePaneZoom(
            workspaceId: context.workspaceId,
            paneId: context.paneId,
            workspaces: &workspaces,
            persistence: persistence
        )
    }

    /// Advances pane tab focus by a signed step with wraparound.
    private func focusAdjacentSurfaceInPane(step: Int) {
        guard step != 0 else { return }
        guard let workspaceId = window.selectedWorkspaceId else { return }
        guard let workspace = self.workspace(id: workspaceId) else { return }
        guard let currentSurfaceId = workspace.focusedSurfaceId else { return }
        guard let paneId = workspace.rootPane.paneId(containing: currentSurfaceId) else { return }
        guard let surfaceIds = workspace.rootPane.surfaceIds(in: paneId), !surfaceIds.isEmpty else { return }
        guard let currentIndex = surfaceIds.firstIndex(of: currentSurfaceId) else { return }

        let rawIndex = currentIndex + step
        let normalizedIndex = (rawIndex % surfaceIds.count + surfaceIds.count) % surfaceIds.count
        let nextSurfaceId = surfaceIds[normalizedIndex]

        activateSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: nextSurfaceId)
    }

    /// Returns the currently focused pane identifier for a workspace.
    private func focusedPaneId(in workspace: WorkspaceModel) -> UUID? {
        guard let focusedSurfaceId = workspace.focusedSurfaceId else { return nil }
        return workspace.rootPane.paneId(containing: focusedSurfaceId)
    }

    /// Returns the best available focused surface identifier for command routing.
    private func focusedSurfaceId() -> UUID? {
        if let surfaceId = currentResponderSurfaceId() {
            return surfaceId
        }

        guard let workspaceId = window.selectedWorkspaceId,
              let workspace = self.workspace(id: workspaceId) else {
            return nil
        }

        return workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId()
    }

    /// Returns whether a specific pane command can run in a resolved context.
    private func canPerformPaneCommand(_ command: FocusedPaneCommand, context: PaneCommandContext) -> Bool {
        switch command {
        case .newSurface, .split, .toggleZoom:
            return context.workspace.rootPane.containsPane(context.paneId)
        case .closeActiveItem:
            return closeSurfaceId(for: context) != nil
        case .focus(let direction):
            return context.workspace.rootPane.adjacentPaneId(
                from: context.paneId,
                direction: direction
            ) != nil
        case .nextSurface, .previousSurface:
            guard let surfaceIds = context.workspace.rootPane.surfaceIds(in: context.paneId) else {
                return false
            }
            return surfaceIds.count > 1
        }
    }

    /// Executes a specific pane command in a resolved context.
    @discardableResult
    private func performPaneCommand(_ command: FocusedPaneCommand, context: PaneCommandContext) -> Bool {
        guard canPerformPaneCommand(command, context: context) else { return false }

        switch command {
        case .newSurface:
            addSurface(
                workspaceId: context.workspaceId,
                paneId: context.paneId,
                surface: configuredDefaultSurface()
            )
        case .split(let orientation):
            splitPane(workspaceId: context.workspaceId, paneId: context.paneId, orientation: orientation)
        case .closeActiveItem:
            guard let surfaceId = closeSurfaceId(for: context) else { return false }
            closeSurface(workspaceId: context.workspaceId, paneId: context.paneId, surfaceId: surfaceId)
        case .focus(let direction):
            guard let targetPaneId = context.workspace.rootPane.adjacentPaneId(
                from: context.paneId,
                direction: direction
            ),
            let targetSurfaceId = context.workspace.rootPane.activeSurfaceId(in: targetPaneId) else {
                return false
            }
            activateSurface(workspaceId: context.workspaceId, paneId: targetPaneId, surfaceId: targetSurfaceId)
        case .nextSurface:
            cycleSurface(in: context, step: 1)
        case .previousSurface:
            cycleSurface(in: context, step: -1)
        case .toggleZoom:
            surfaceManager.togglePaneZoom(
                workspaceId: context.workspaceId,
                paneId: context.paneId,
                workspaces: &workspaces,
                persistence: persistence
            )
        }

        return true
    }

    /// Returns the close target surface for the resolved pane context.
    private func closeSurfaceId(for context: PaneCommandContext) -> UUID? {
        if let surfaceId = context.surfaceId,
           context.workspace.rootPane.paneId(containing: surfaceId) == context.paneId {
            return surfaceId
        }

        return context.workspace.rootPane.activeSurfaceId(in: context.paneId)
    }

    /// Returns the close command title for the resolved pane context.
    private func closeItemTitle(for context: PaneCommandContext) -> String {
        guard let surfaceIds = context.workspace.rootPane.surfaceIds(in: context.paneId) else {
            return "Close Active Pane/Tab"
        }

        if context.surfaceId != nil || surfaceIds.count > 1 {
            return "Close Active Tab"
        }

        return "Close Active Pane"
    }

    /// Advances tab focus within a specific pane context.
    private func cycleSurface(in context: PaneCommandContext, step: Int) {
        guard step != 0 else { return }
        guard let surfaceIds = context.workspace.rootPane.surfaceIds(in: context.paneId), !surfaceIds.isEmpty else {
            return
        }

        let currentSurfaceId = context.surfaceId
            ?? context.workspace.rootPane.activeSurfaceId(in: context.paneId)
            ?? surfaceIds.first
        guard let currentSurfaceId,
              let currentIndex = surfaceIds.firstIndex(of: currentSurfaceId) else {
            return
        }

        let rawIndex = currentIndex + step
        let normalizedIndex = (rawIndex % surfaceIds.count + surfaceIds.count) % surfaceIds.count
        let nextSurfaceId = surfaceIds[normalizedIndex]

        activateSurface(workspaceId: context.workspaceId, paneId: context.paneId, surfaceId: nextSurfaceId)
    }

    /// Returns a resolved pane command context for an explicit pane or tab target.
    private func paneCommandContext(
        workspaceId: UUID,
        paneId: UUID,
        surfaceId: UUID? = nil
    ) -> PaneCommandContext? {
        guard let workspace = self.workspace(id: workspaceId),
              workspace.rootPane.containsPane(paneId) else {
            return nil
        }

        if let surfaceId,
           workspace.rootPane.paneId(containing: surfaceId) != paneId {
            return nil
        }

        return PaneCommandContext(
            workspaceId: workspaceId,
            workspace: workspace,
            paneId: paneId,
            surfaceId: surfaceId
        )
    }

    /// Builds the standard surface model used by app-driven surface creation flows.
    private func configuredDefaultSurface() -> SurfaceModel {
        var surface = SurfaceModel.makeDefault()
        surface.terminalConfig.workingDirectory = NSHomeDirectory()
        return surface
    }

    /// Returns focused pane context resolved from responder, workspace, and pane state.
    private func focusedPaneContext() -> PaneCommandContext? {
        guard let workspaceId = window.selectedWorkspaceId,
              let workspace = self.workspace(id: workspaceId) else {
            return nil
        }

        if let sourceSurfaceId = currentResponderSurfaceId(),
           let paneId = workspace.rootPane.paneId(containing: sourceSurfaceId) {
            return PaneCommandContext(
                workspaceId: workspaceId,
                workspace: workspace,
                paneId: paneId,
                surfaceId: sourceSurfaceId
            )
        }

        guard let paneId = focusedPaneId(in: workspace) ?? workspace.rootPane.firstLeafId() else {
            return nil
        }

        return PaneCommandContext(
            workspaceId: workspaceId,
            workspace: workspace,
            paneId: paneId,
            surfaceId: workspace.rootPane.activeSurfaceId(in: paneId)
        )
    }

    /// Returns the surface id of the current first-responder terminal view, if any.
    func currentResponderSurfaceId() -> UUID? {
        guard let responder = NSApp.keyWindow?.firstResponder else { return nil }

        if let host = responder as? LibghosttySurfaceView {
            return host.surfaceId
        }

        guard let viewResponder = responder as? NSView else { return nil }
        var view: NSView? = viewResponder
        while let current = view {
            if let host = current as? LibghosttySurfaceView {
                return host.surfaceId
            }
            view = current.superview
        }

        return nil
    }
}
