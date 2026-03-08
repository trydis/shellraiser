import AppKit
import Foundation

/// Executes a synchronous scripting access on the main thread while preserving a simple Objective-C surface.
private func withMainActorValue<T>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            body()
        }
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            body()
        }
    }
}

/// Mutable AppleScript configuration object used when creating scripted surfaces.
@objc(ScriptableSurfaceConfiguration)
final class ScriptableSurfaceConfiguration: NSObject {
    private let identifier = UUID().uuidString.lowercased()

    /// Stable identifier used by AppleScript object specifiers.
    @objc dynamic var id: String {
        identifier
    }

    /// Initial working directory applied to newly created surfaces.
    @objc dynamic var initialWorkingDirectory: String = NSHomeDirectory()

    /// Returns a unique-id object specifier so AppleScript can reuse the configuration object.
    @MainActor
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let applicationClass = NSScriptClassDescription(for: NSApplication.self) else {
            return nil
        }

        return NSUniqueIDSpecifier(
            containerClassDescription: applicationClass,
            containerSpecifier: nil,
            key: "surfaceConfigurations",
            uniqueID: id
        )
    }
}

/// Immutable scripting snapshot for a workspace object.
struct ScriptableWorkspaceSnapshot: Identifiable, Equatable {
    let workspaceId: UUID
    let name: String

    /// Stable identifier for the workspace wrapper.
    var id: String {
        workspaceId.uuidString.lowercased()
    }
}

/// Immutable scripting snapshot for a workspace tab wrapper.
struct ScriptableTabSnapshot: Identifiable, Equatable {
    let workspaceId: UUID
    let paneId: UUID
    let surfaceId: UUID
    let title: String
    let workingDirectory: String

    /// Stable identifier for the tab wrapper.
    var id: String {
        surfaceId.uuidString.lowercased()
    }
}

/// Scriptable workspace wrapper used by Shellraiser-specific AppleScript commands.
@objc(ScriptableWorkspace)
final class ScriptableWorkspace: NSObject {
    private let snapshot: ScriptableWorkspaceSnapshot

    /// Creates a scriptable workspace wrapper around a workspace snapshot.
    init(snapshot: ScriptableWorkspaceSnapshot) {
        self.snapshot = snapshot
    }

    /// User-visible workspace name.
    @objc dynamic var name: String {
        snapshot.name
    }

    /// Stable workspace identifier.
    @objc dynamic var id: String {
        snapshot.id
    }

    /// Selected tab for the workspace.
    @objc dynamic var selectedTab: ScriptableTab? {
        withMainActorValue {
            ShellraiserScriptingController.shared.selectedTab(workspaceId: snapshot.workspaceId)
        }
    }

    /// All tabs in the workspace.
    @objc dynamic var tabs: [ScriptableTab] {
        withMainActorValue {
            ShellraiserScriptingController.shared.tabs(workspaceId: snapshot.workspaceId)
        }
    }

    /// Returns the number of tabs for AppleScript collection access.
    @objc var countOfTabs: Int {
        tabs.count
    }

    /// Returns one tab by index for AppleScript collection access.
    @objc(objectInTabsAtIndex:)
    func objectInTabs(at index: Int) -> ScriptableTab {
        tabs[index]
    }

    /// Returns a unique-id object specifier for the app-level workspaces collection.
    override var objectSpecifier: NSScriptObjectSpecifier? {
        withMainActorValue {
            guard let applicationClass = NSScriptClassDescription(for: NSApplication.self) else {
                return nil
            }

            return NSUniqueIDSpecifier(
                containerClassDescription: applicationClass,
                containerSpecifier: nil,
                key: "workspaces",
                uniqueID: id
            )
        }
    }
}

/// Scriptable tab wrapper over a single surface entry inside a workspace pane leaf.
@objc(ScriptableTab)
final class ScriptableTab: NSObject {
    private let snapshot: ScriptableTabSnapshot

    /// Creates a scriptable tab wrapper around a surface snapshot.
    init(snapshot: ScriptableTabSnapshot) {
        self.snapshot = snapshot
    }

    /// User-visible tab title.
    @objc dynamic var name: String {
        snapshot.title
    }

    /// Selected terminal for this tab.
    @objc dynamic var terminals: [ScriptableTerminal] {
        withMainActorValue {
            [ScriptableTerminal(snapshot: ScriptableTerminalSnapshot(
                workspaceId: snapshot.workspaceId,
                paneId: snapshot.paneId,
                surfaceId: snapshot.surfaceId,
                title: snapshot.title,
                workingDirectory: snapshot.workingDirectory
            ))]
        }
    }

    /// Returns the number of terminals in the tab.
    @objc var countOfTerminals: Int {
        terminals.count
    }

    /// Returns the terminal in the tab for AppleScript collection access.
    @objc(objectInTerminalsAtIndex:)
    func objectInTerminals(at index: Int) -> ScriptableTerminal {
        terminals[index]
    }

    /// Returns an index-based object specifier for the parent workspace's tabs collection.
    override var objectSpecifier: NSScriptObjectSpecifier? {
        withMainActorValue {
            guard let container = ShellraiserScriptingController.shared.workspace(workspaceId: snapshot.workspaceId),
                  let containerSpecifier = container.objectSpecifier,
                  let workspaceClass = NSScriptClassDescription(for: ScriptableWorkspace.self) else {
                return nil
            }

            guard let index = ShellraiserScriptingController.shared.tabIndex(
                workspaceId: snapshot.workspaceId,
                surfaceId: snapshot.surfaceId
            ) else {
                return nil
            }

            return NSIndexSpecifier(
                containerClassDescription: workspaceClass,
                containerSpecifier: containerSpecifier,
                key: "tabs",
                index: index
            )
        }
    }
}

/// Cocoa scripting object that represents one open terminal surface.
@objc(ScriptableTerminal)
final class ScriptableTerminal: NSObject {
    private let snapshot: ScriptableTerminalSnapshot

    /// Creates a scriptable wrapper around a surface snapshot.
    init(snapshot: ScriptableTerminalSnapshot) {
        self.snapshot = snapshot
    }

    /// Stable surface identifier returned to AppleScript callers.
    @objc dynamic var id: String {
        snapshot.id
    }

    /// User-visible title for the terminal tab.
    @objc dynamic var title: String {
        snapshot.title
    }

    /// Ghostty-style terminal name alias used by filtered AppleScript queries.
    @objc dynamic var name: String {
        snapshot.title
    }

    /// Current working directory for the terminal session.
    @objc dynamic var workingDirectory: String {
        snapshot.workingDirectory
    }

    /// Underlying surface identifier used for command routing.
    var surfaceId: UUID {
        snapshot.surfaceId
    }

    /// Returns an index-based object specifier so AppleScript can refer back to this terminal.
    @MainActor
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let applicationClass = NSScriptClassDescription(for: NSApplication.self) else {
            return nil
        }

        guard let index = ShellraiserScriptingController.shared.terminalIndex(surfaceId: surfaceId) else {
            return nil
        }

        return NSIndexSpecifier(
            containerClassDescription: applicationClass,
            containerSpecifier: nil,
            key: "terminals",
            index: index
        )
    }

    /// Handles the object-targeted AppleScript `focus` command.
    @objc(handleFocusScriptCommand:)
    @MainActor
    func handleFocusScriptCommand(_ command: NSScriptCommand) -> Any? {
        guard ShellraiserScriptingController.shared.focus(terminal: self) else {
            command.scriptErrorNumber = NSReceiverEvaluationScriptError
            command.scriptErrorString = "Shellraiser could not focus the requested terminal."
            return nil
        }

        return nil
    }

    /// Handles the object-targeted AppleScript `input text` command.
    @objc(handleInputTextScriptCommand:)
    @MainActor
    func handleInputTextScriptCommand(_ command: NSScriptCommand) -> Any? {
        let text = (command.directParameter as? String) ?? (command.evaluatedArguments?["text"] as? String)
        guard let text else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The input text command requires a text parameter."
            return nil
        }

        guard ShellraiserScriptingController.shared.input(text: text, to: self) else {
            command.scriptErrorNumber = NSReceiverEvaluationScriptError
            command.scriptErrorString = "Shellraiser could not find the requested terminal."
            return nil
        }

        return nil
    }

    /// Handles the object-targeted AppleScript `send key` command.
    @objc(handleSendKeyScriptCommand:)
    @MainActor
    func handleSendKeyScriptCommand(_ command: NSScriptCommand) -> Any? {
        let keyName = (command.directParameter as? String) ?? (command.evaluatedArguments?["key"] as? String)
        guard let keyName else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The send key command requires a key name."
            return nil
        }

        guard ShellraiserScriptingController.shared.sendKey(named: keyName, to: self) else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "Unsupported key name or missing terminal."
            return nil
        }

        return nil
    }

    /// Handles the object-targeted AppleScript `split` command.
    @objc(handleSplitScriptCommand:)
    @MainActor
    func handleSplitScriptCommand(_ command: NSScriptCommand) -> Any? {
        let directionValue = command.evaluatedArguments?["direction"]
        let direction = (directionValue as? String) ?? String(describing: directionValue ?? "")
        let configuration = command.evaluatedArguments?["configuration"] as? ScriptableSurfaceConfiguration

        guard let created = ShellraiserScriptingController.shared.split(
            terminal: self,
            direction: direction,
            configuration: configuration
        ) else {
            command.scriptErrorNumber = NSReceiverEvaluationScriptError
            command.scriptErrorString = "Shellraiser could not split the requested terminal."
            return nil
        }

        return created
    }
}
