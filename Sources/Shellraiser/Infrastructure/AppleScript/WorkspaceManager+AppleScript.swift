import AppKit
import Foundation

/// AppleScript-oriented surface discovery and command routing helpers.
extension WorkspaceManager {
    /// Returns one scripting snapshot for every workspace.
    func scriptableWorkspaceSnapshots() -> [ScriptableWorkspaceSnapshot] {
        workspaces.map { workspace in
            ScriptableWorkspaceSnapshot(
                workspaceId: workspace.id,
                name: workspace.name
            )
        }
    }

    /// Prevents duplicate load cycles when UI and AppleScript both touch startup state.
    func ensureWorkspacesLoaded() {
        guard !hasLoadedPersistedWorkspaces else { return }
        loadWorkspaces()
    }

    /// Returns one scripting snapshot for every currently open terminal surface.
    func scriptableTerminalSnapshots() -> [ScriptableTerminalSnapshot] {
        workspaces.flatMap { workspace in
            workspace.rootPane.scriptableTerminalSnapshots(workspaceId: workspace.id)
        }
    }

    /// Returns one scripting snapshot for every tab in a workspace.
    func scriptableTabSnapshots(workspaceId: UUID) -> [ScriptableTabSnapshot] {
        guard let workspace = workspace(id: workspaceId) else { return [] }
        return workspace.rootPane.scriptableTabSnapshots(workspaceId: workspace.id)
    }

    /// Returns the selected tab snapshot for a workspace.
    func selectedScriptableTabSnapshot(workspaceId: UUID) -> ScriptableTabSnapshot? {
        guard let workspace = workspace(id: workspaceId) else { return nil }
        let selectedSurfaceId = workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId()
        guard let selectedSurfaceId,
              let snapshot = workspace.rootPane.scriptableTabSnapshots(workspaceId: workspace.id)
                .first(where: { $0.surfaceId == selectedSurfaceId }) else {
            return nil
        }
        return snapshot
    }

    /// Sends literal text to a specific surface after activating its pane context.
    @discardableResult
    func sendScriptText(_ text: String, toSurfaceId surfaceId: UUID) -> Bool {
        guard let target = surfaceContext(for: surfaceId) else { return false }
        guard !text.isEmpty else { return true }

        focusScriptSurface(target)
        let didSend = GhosttyRuntime.shared.sendText(surfaceId: target.surfaceId, text: text)
        if didSend {
            noteSurfaceActivity(workspaceId: target.workspaceId, surfaceId: target.surfaceId)
        }
        return didSend
    }

    /// Sends a named key to a specific surface after activating its pane context.
    @discardableResult
    func sendScriptKey(named keyName: String, toSurfaceId surfaceId: UUID) -> Bool {
        guard let target = surfaceContext(for: surfaceId) else { return false }

        focusScriptSurface(target)
        let didSend = GhosttyRuntime.shared.sendNamedKey(surfaceId: target.surfaceId, keyName: keyName)
        if didSend {
            noteSurfaceActivity(workspaceId: target.workspaceId, surfaceId: target.surfaceId)
        }
        return didSend
    }

    /// Focuses a specific script-targeted surface without sending input.
    @discardableResult
    func focusScriptSurface(surfaceId: UUID) -> Bool {
        guard let target = surfaceContext(for: surfaceId) else { return false }
        focusScriptSurface(target)
        return true
    }

    /// Creates a new workspace and applies the provided surface configuration.
    func createScriptWindow(configuration: ScriptableSurfaceConfiguration?) -> UUID? {
        let workspace = createWorkspace(
            name: "Workspace",
            initialSurface: makeScriptSurface(configuration: configuration)
        )
        selectWorkspace(workspace.id)

        return workspace.id
    }

    /// Splits the pane owning a scripted terminal and returns the newly created terminal snapshot.
    func splitScriptTerminal(
        surfaceId: UUID,
        direction: String,
        configuration: ScriptableSurfaceConfiguration?
    ) -> ScriptableTerminalSnapshot? {
        guard let target = surfaceContext(for: surfaceId) else { return nil }
        guard let placement = scriptSplitPlacement(direction: direction) else { return nil }

        var createdSurfaceId: UUID?
        createdSurfaceId = surfaceManager.splitPane(
            workspaceId: target.workspaceId,
            paneId: target.paneId,
            orientation: placement.orientation,
            position: placement.position,
            newSurface: makeScriptSurface(configuration: configuration),
            workspaces: &workspaces,
            persistence: persistence
        )

        guard let createdSurfaceId else { return nil }

        guard let createdContext = surfaceContext(for: createdSurfaceId),
              let snapshot = scriptableTerminalSnapshots().first(where: { $0.surfaceId == createdSurfaceId }) else {
            return nil
        }

        focusScriptSurface(createdContext)
        return snapshot
    }

    /// Resolves the workspace and pane that own a specific surface.
    private func surfaceContext(for surfaceId: UUID) -> ScriptSurfaceContext? {
        for workspace in workspaces {
            guard let paneId = workspace.rootPane.paneId(containing: surfaceId) else {
                continue
            }

            return ScriptSurfaceContext(
                workspaceId: workspace.id,
                paneId: paneId,
                surfaceId: surfaceId
            )
        }

        return nil
    }
}

/// Lightweight lookup context for script-targeted surfaces.
private struct ScriptSurfaceContext {
    let workspaceId: UUID
    let paneId: UUID
    let surfaceId: UUID
}

/// Pane-tree traversal helpers used to expose all surface snapshots to AppleScript.
private extension PaneNodeModel {
    /// Collects tab snapshots across the full pane tree.
    func scriptableTabSnapshots(workspaceId: UUID) -> [ScriptableTabSnapshot] {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.map { surface in
                ScriptableTabSnapshot(
                    workspaceId: workspaceId,
                    paneId: leaf.id,
                    surfaceId: surface.id,
                    title: surface.title,
                    workingDirectory: surface.terminalConfig.workingDirectory
                )
            }
        case .split(let split):
            return split.first.scriptableTabSnapshots(workspaceId: workspaceId)
                + split.second.scriptableTabSnapshots(workspaceId: workspaceId)
        }
    }

    /// Collects terminal snapshots across the full pane tree.
    func scriptableTerminalSnapshots(workspaceId: UUID) -> [ScriptableTerminalSnapshot] {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.map { surface in
                ScriptableTerminalSnapshot(
                    workspaceId: workspaceId,
                    paneId: leaf.id,
                    surfaceId: surface.id,
                    title: surface.title,
                    workingDirectory: surface.terminalConfig.workingDirectory
                )
            }
        case .split(let split):
            return split.first.scriptableTerminalSnapshots(workspaceId: workspaceId)
                + split.second.scriptableTerminalSnapshots(workspaceId: workspaceId)
        }
    }
}

private extension WorkspaceManager {
    /// Split metadata resolved from AppleScript direction strings.
    struct ScriptSplitPlacement {
        let orientation: SplitOrientation
        let position: SplitChildPosition
    }

    /// Builds a surface model for AppleScript-driven creation flows.
    func makeScriptSurface(configuration: ScriptableSurfaceConfiguration?) -> SurfaceModel {
        var surface = SurfaceModel.makeDefault()
        if let configuration {
            surface.terminalConfig.workingDirectory = configuration.initialWorkingDirectory
        }
        return surface
    }

    /// Maps script split directions onto pane orientation and insertion position.
    func scriptSplitPlacement(direction: String) -> ScriptSplitPlacement? {
        switch direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left":
            return ScriptSplitPlacement(orientation: .horizontal, position: .first)
        case "right":
            return ScriptSplitPlacement(orientation: .horizontal, position: .second)
        case "up":
            return ScriptSplitPlacement(orientation: .vertical, position: .first)
        case "down":
            return ScriptSplitPlacement(orientation: .vertical, position: .second)
        default:
            return nil
        }
    }

    /// Applies workspace selection and pane activation for a resolved script surface.
    func focusScriptSurface(_ context: ScriptSurfaceContext) {
        NSApp.activate(ignoringOtherApps: true)
        GhosttyRuntime.shared.setAppFocus(true)
        selectWorkspace(context.workspaceId)
        activateSurface(
            workspaceId: context.workspaceId,
            paneId: context.paneId,
            surfaceId: context.surfaceId
        )
    }
}
