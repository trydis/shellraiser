import AppKit
import Foundation

/// Immutable snapshot of a terminal surface exposed through AppleScript.
struct ScriptableTerminalSnapshot: Identifiable, Equatable {
    let workspaceId: UUID
    let paneId: UUID
    let surfaceId: UUID
    let title: String
    let workingDirectory: String

    /// Stable identifier used by scripting object specifiers.
    var id: String {
        surfaceId.uuidString.lowercased()
    }
}

/// Main-actor bridge between Cocoa scripting commands and workspace state.
@MainActor
final class ShellraiserScriptingController {
    static let shared = ShellraiserScriptingController()

    private weak var workspaceManager: WorkspaceManager?
    private var surfaceConfigurationsByID: [String: ScriptableSurfaceConfiguration] = [:]

    private init() {}

    /// Installs the current workspace manager used to resolve script commands.
    func install(workspaceManager: WorkspaceManager) {
        self.workspaceManager = workspaceManager
    }

    /// Forwards app-termination preparation to the installed workspace manager.
    func prepareForTermination() {
        workspaceManager?.prepareForTermination()
    }

    /// Returns scriptable terminal objects for every open terminal surface.
    func terminals() -> [ScriptableTerminal] {
        terminalSnapshots().map(ScriptableTerminal.init(snapshot:))
    }

    /// Returns scriptable workspaces for every workspace.
    func workspaces() -> [ScriptableWorkspace] {
        workspaceSnapshots().map(ScriptableWorkspace.init(snapshot:))
    }

    /// Returns one scriptable workspace by stable identifier.
    func workspace(id: String) -> ScriptableWorkspace? {
        workspaceSnapshots()
            .first { $0.id == id.lowercased() }
            .map(ScriptableWorkspace.init(snapshot:))
    }

    /// Returns one scriptable workspace by workspace identifier.
    func workspace(workspaceId: UUID) -> ScriptableWorkspace? {
        workspaceSnapshots()
            .first { $0.workspaceId == workspaceId }
            .map(ScriptableWorkspace.init(snapshot:))
    }

    /// Returns all tabs in one workspace.
    func tabs(workspaceId: UUID) -> [ScriptableTab] {
        tabSnapshots(workspaceId: workspaceId).map(ScriptableTab.init(snapshot:))
    }

    /// Returns the currently selected tab in a workspace.
    func selectedTab(workspaceId: UUID) -> ScriptableTab? {
        selectedTabSnapshot(workspaceId: workspaceId).map(ScriptableTab.init(snapshot:))
    }

    /// Returns the current positional index for a tab inside a workspace.
    func tabIndex(workspaceId: UUID, surfaceId: UUID) -> Int? {
        tabSnapshots(workspaceId: workspaceId).firstIndex { $0.surfaceId == surfaceId }
    }

    /// Focuses the target terminal surface in the active Shellraiser window.
    @discardableResult
    func focus(terminal: ScriptableTerminal) -> Bool {
        guard let manager = workspaceManager else { return false }
        return manager.focusScriptSurface(surfaceId: terminal.surfaceId)
    }

    /// Sends literal text to the target terminal surface.
    @discardableResult
    func input(text: String, to terminal: ScriptableTerminal) -> Bool {
        guard let manager = workspaceManager else { return false }
        return manager.sendScriptText(text, toSurfaceId: terminal.surfaceId)
    }

    /// Sends a named key through a conservative text-based mapping.
    @discardableResult
    func sendKey(named keyName: String, to terminal: ScriptableTerminal) -> Bool {
        guard let manager = workspaceManager else { return false }
        return manager.sendScriptKey(named: keyName, toSurfaceId: terminal.surfaceId)
    }

    /// Returns the current terminal surface snapshot for a specific identifier.
    func terminalSnapshot(surfaceId: UUID) -> ScriptableTerminalSnapshot? {
        terminalSnapshots().first { $0.surfaceId == surfaceId }
    }

    /// Returns the current positional index for a terminal surface in the scriptable collection.
    func terminalIndex(surfaceId: UUID) -> Int? {
        terminalSnapshots().firstIndex { $0.surfaceId == surfaceId }
    }

    /// Creates a fresh scripting configuration object with default values.
    func newSurfaceConfiguration() -> ScriptableSurfaceConfiguration {
        let configuration = ScriptableSurfaceConfiguration()
        surfaceConfigurationsByID[configuration.id] = configuration
        return configuration
    }

    /// Returns all live scripting configuration objects retained for AppleScript references.
    func surfaceConfigurations() -> [ScriptableSurfaceConfiguration] {
        surfaceConfigurationsByID.values.sorted { $0.id < $1.id }
    }

    /// Resolves a retained surface configuration by unique identifier.
    func surfaceConfiguration(id: String) -> ScriptableSurfaceConfiguration? {
        surfaceConfigurationsByID[id.lowercased()]
    }

    /// Inserts a surface configuration into the retained scripting collection.
    func insertSurfaceConfiguration(_ configuration: ScriptableSurfaceConfiguration) {
        surfaceConfigurationsByID[configuration.id] = configuration
    }

    /// Creates a new scriptable workspace using an optional name and scripting configuration.
    func newWorkspace(
        name: String? = nil,
        configuration: ScriptableSurfaceConfiguration?
    ) -> ScriptableWorkspace? {
        guard let manager = workspaceManager,
              let workspaceId = manager.createScriptWindow(
                name: name,
                configuration: configuration
              ),
              let snapshot = workspaceSnapshots().first(where: { $0.workspaceId == workspaceId }) else {
            return nil
        }

        return ScriptableWorkspace(snapshot: snapshot)
    }

    /// Splits the pane owning a scripted terminal and returns the newly created terminal.
    func split(
        terminal: ScriptableTerminal,
        direction: String,
        configuration: ScriptableSurfaceConfiguration?
    ) -> ScriptableTerminal? {
        guard let manager = workspaceManager,
              let snapshot = manager.splitScriptTerminal(
                surfaceId: terminal.surfaceId,
                direction: direction,
                configuration: configuration
              ) else {
            return nil
        }

        return ScriptableTerminal(snapshot: snapshot)
    }

    /// Lazily loads persisted workspaces before any script-driven access.
    private func terminalSnapshots() -> [ScriptableTerminalSnapshot] {
        guard let manager = workspaceManager else { return [] }

        manager.ensureWorkspacesLoaded()
        return manager.scriptableTerminalSnapshots()
    }

    /// Returns all scriptable workspace snapshots.
    private func workspaceSnapshots() -> [ScriptableWorkspaceSnapshot] {
        guard let manager = workspaceManager else { return [] }

        manager.ensureWorkspacesLoaded()
        return manager.scriptableWorkspaceSnapshots()
    }

    /// Returns all scriptable tab snapshots for a workspace.
    private func tabSnapshots(workspaceId: UUID) -> [ScriptableTabSnapshot] {
        guard let manager = workspaceManager else { return [] }

        manager.ensureWorkspacesLoaded()
        return manager.scriptableTabSnapshots(workspaceId: workspaceId)
    }

    /// Returns the currently selected tab snapshot for a workspace.
    private func selectedTabSnapshot(workspaceId: UUID) -> ScriptableTabSnapshot? {
        guard let manager = workspaceManager else { return nil }

        manager.ensureWorkspacesLoaded()
        return manager.selectedScriptableTabSnapshot(workspaceId: workspaceId)
    }
}
