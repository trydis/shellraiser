import SwiftUI
import AppKit

/// App delegate that confirms before allowing the application to terminate.
@MainActor
final class ShellraiserAppDelegate: NSObject, NSApplicationDelegate {
    /// Test seam used to override quit confirmation without presenting AppKit UI.
    var confirmQuit: () -> Bool = {
        let alert = NSAlert()
        alert.messageText = "Quit Shellraiser?"
        alert.informativeText = "All workspaces and terminal sessions will be closed."
        alert.addButton(withTitle: "Quit Shellraiser")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Routes top-level AppleScript keys to the app delegate.
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "terminals" || key == "surfaceConfigurations" || key == "workspaces"
    }

    /// Exposes the current set of open terminal surfaces to AppleScript.
    @objc var terminals: [ScriptableTerminal] {
        ShellraiserScriptingController.shared.terminals()
    }

    /// Exposes the current set of workspaces to AppleScript.
    @objc var workspaces: [ScriptableWorkspace] {
        ShellraiserScriptingController.shared.workspaces()
    }

    /// Returns the number of open terminals for AppleScript count evaluation.
    @objc var countOfTerminals: Int {
        terminals.count
    }

    /// Resolves a terminal by positional index for AppleScript collection access.
    @objc(objectInTerminalsAtIndex:)
    func objectInTerminals(at index: Int) -> ScriptableTerminal {
        terminals[index]
    }

    /// Resolves a terminal by stable unique identifier for AppleScript object specifiers.
    @objc(valueInTerminalsWithUniqueID:)
    func valueInTerminals(withUniqueID uniqueID: String) -> ScriptableTerminal? {
        terminals.first { $0.id == uniqueID.lowercased() }
    }

    /// Returns the number of workspaces for AppleScript count evaluation.
    @objc var countOfWorkspaces: Int {
        workspaces.count
    }

    /// Resolves a workspace by positional index for AppleScript collection access.
    @objc(objectInWorkspacesAtIndex:)
    func objectInWorkspaces(at index: Int) -> ScriptableWorkspace {
        workspaces[index]
    }

    /// Resolves a workspace by stable unique identifier.
    @objc(valueInWorkspacesWithUniqueID:)
    func valueInWorkspaces(withUniqueID uniqueID: String) -> ScriptableWorkspace? {
        ShellraiserScriptingController.shared.workspace(id: uniqueID)
    }

    /// Exposes retained surface configuration objects to AppleScript.
    @objc var surfaceConfigurations: [ScriptableSurfaceConfiguration] {
        ShellraiserScriptingController.shared.surfaceConfigurations()
    }

    /// Returns the number of retained surface configurations for AppleScript count evaluation.
    @objc var countOfSurfaceConfigurations: Int {
        surfaceConfigurations.count
    }

    /// Resolves a retained surface configuration by positional index.
    @objc(objectInSurfaceConfigurationsAtIndex:)
    func objectInSurfaceConfigurations(at index: Int) -> ScriptableSurfaceConfiguration {
        surfaceConfigurations[index]
    }

    /// Resolves a retained surface configuration by stable unique identifier.
    @objc(valueInSurfaceConfigurationsWithUniqueID:)
    func valueInSurfaceConfigurations(withUniqueID uniqueID: String) -> ScriptableSurfaceConfiguration? {
        ShellraiserScriptingController.shared.surfaceConfiguration(id: uniqueID)
    }

    /// Inserts a newly scripted surface configuration into the retained collection.
    @objc(insertInSurfaceConfigurations:atIndex:)
    func insertInSurfaceConfigurations(_ configuration: ScriptableSurfaceConfiguration, at index: Int) {
        _ = index
        ShellraiserScriptingController.shared.insertSurfaceConfiguration(configuration)
    }

    /// Intercepts standard app termination and requires explicit user confirmation.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard confirmQuit() else {
            return .terminateCancel
        }

        ShellraiserScriptingController.shared.prepareForTermination()
        return .terminateNow
    }
}

/// Application entry point for the Shellraiser macOS app.
@main
struct ShellraiserApp: App {
    @NSApplicationDelegateAdaptor(ShellraiserAppDelegate.self) private var appDelegate
    @StateObject private var manager: WorkspaceManager

    /// Disables native macOS window tabbing so the app's own pane tabs remain the only tab UI.
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let manager = WorkspaceManager()
        _manager = StateObject(wrappedValue: manager)
        ShellraiserScriptingController.shared.install(workspaceManager: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            WorkspaceCommands(manager: manager)
        }
    }
}

/// Menu-bar commands and keyboard shortcuts for workspace, pane, and terminal actions.
struct WorkspaceCommands: Commands {
    @ObservedObject var manager: WorkspaceManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Workspace") {
                _ = manager.createWorkspace(name: "Workspace")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(after: .sidebar) {
            Button("Command Palette") {
                manager.toggleCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Workspace") {
            Button("New Workspace") {
                _ = manager.createWorkspace(name: "Workspace")
            }

            Divider()

            Button("Rename Active Workspace") {
                manager.requestRenameSelectedWorkspace()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(manager.selectedWorkspace == nil)

            Button("Delete Active Workspace") {
                manager.requestDeleteSelectedWorkspace()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(manager.selectedWorkspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Switch to Workspace \(number)") {
                    manager.selectWorkspace(atDisplayIndex: number)
                }
                .keyboardShortcut(Self.keyEquivalent(for: number), modifiers: [.command])
                .disabled(!manager.hasWorkspace(atDisplayIndex: number))
            }

            Divider()

            Button("Jump to Next Completed Session") {
                manager.jumpToNextCompletedSession()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!manager.hasPendingCompletions)
        }

        CommandMenu("Pane") {
            Button("New Surface") {
                _ = manager.performFocusedPaneCommand(.newSurface)
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.newSurface))

            Button("Split Horizontally") {
                _ = manager.performFocusedPaneCommand(.split(.horizontal))
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.split(.horizontal)))

            Button("Split Vertically") {
                _ = manager.performFocusedPaneCommand(.split(.vertical))
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.split(.vertical)))

            Divider()

            Button(manager.closeFocusedItemTitle) {
                _ = manager.performFocusedPaneCommand(.closeActiveItem)
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.closeActiveItem))

            Divider()

            Button("Focus Left Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.left))
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.left)))

            Button("Focus Right Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.right))
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.right)))

            Button("Focus Up Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.up))
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.up)))

            Button("Focus Down Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.down))
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.down)))

            Divider()

            Button("Next Tab In Pane") {
                _ = manager.performFocusedPaneCommand(.nextSurface)
            }
            .keyboardShortcut(.tab, modifiers: [.control])
            .disabled(!manager.canPerformFocusedPaneCommand(.nextSurface))

            Button("Previous Tab In Pane") {
                _ = manager.performFocusedPaneCommand(.previousSurface)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.previousSurface))

            Divider()

            Button("Toggle Split Zoom") {
                _ = manager.performFocusedPaneCommand(.toggleZoom)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.toggleZoom))
        }

        CommandMenu("Terminal") {
            Button("Reset Terminal") {
                manager.performFocusedSurfaceBindingAction("reset")
            }
            .disabled(!manager.hasFocusedSurface)

            Divider()

            Button("Increase Font Size") {
                manager.performFocusedSurfaceBindingAction("increase_font_size:1")
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)

            Button("Decrease Font Size") {
                manager.performFocusedSurfaceBindingAction("decrease_font_size:1")
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)

            Button("Reset Font Size") {
                manager.performFocusedSurfaceBindingAction("reset_font_size")
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)
        }
    }

    /// Maps workspace indices to numeric key equivalents for shortcuts.
    private static func keyEquivalent(for number: Int) -> KeyEquivalent {
        switch number {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        case 4: return "4"
        case 5: return "5"
        case 6: return "6"
        case 7: return "7"
        case 8: return "8"
        case 9: return "9"
        default: return "0"
        }
    }
}

/// Cocoa scripting hooks exposed directly on the application object.
extension NSApplication {
    /// Handles the application-targeted AppleScript `input` command.
    @objc(handleInputScriptCommand:)
    @MainActor
    func handleInputScriptCommand(_ command: NSScriptCommand) -> Any? {
        let text = (command.directParameter as? String) ?? (command.evaluatedArguments?["text"] as? String)
        guard let text else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The input command requires text."
            return nil
        }

        let terminal = (command.evaluatedArguments?["to"] as? ScriptableTerminal)
            ?? ((command.evaluatedArguments?["to"] as? [ScriptableTerminal])?.first)
        guard let terminal else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The input command requires a terminal target."
            return nil
        }

        guard ShellraiserScriptingController.shared.input(text: text, to: terminal) else {
            command.scriptErrorNumber = NSReceiverEvaluationScriptError
            command.scriptErrorString = "Shellraiser could not find the requested terminal."
            return nil
        }

        return nil
    }

    /// Handles the application-targeted AppleScript `send` command.
    @objc(handleSendScriptCommand:)
    @MainActor
    func handleSendScriptCommand(_ command: NSScriptCommand) -> Any? {
        let keyName = (command.directParameter as? String) ?? (command.evaluatedArguments?["key"] as? String)
        guard let keyName else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The send command requires a key."
            return nil
        }

        let terminal = (command.evaluatedArguments?["to"] as? ScriptableTerminal)
            ?? ((command.evaluatedArguments?["to"] as? [ScriptableTerminal])?.first)
        guard let terminal else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The send command requires a terminal target."
            return nil
        }

        guard ShellraiserScriptingController.shared.sendKey(named: keyName, to: terminal) else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "Unsupported key name or missing terminal."
            return nil
        }

        return nil
    }

    /// Handles the application-targeted AppleScript `focus` command.
    @objc(handleFocusScriptCommand:)
    @MainActor
    func handleFocusScriptCommand(_ command: NSScriptCommand) -> Any? {
        let terminal = (command.directParameter as? ScriptableTerminal)
            ?? (command.evaluatedArguments?["terminal"] as? ScriptableTerminal)
            ?? ((command.evaluatedArguments?["terminal"] as? [ScriptableTerminal])?.first)
        guard let terminal else {
            command.scriptErrorNumber = NSArgumentsWrongScriptError
            command.scriptErrorString = "The focus command requires a terminal."
            return nil
        }

        guard ShellraiserScriptingController.shared.focus(terminal: terminal) else {
            command.scriptErrorNumber = NSReceiverEvaluationScriptError
            command.scriptErrorString = "Shellraiser could not focus the requested terminal."
            return nil
        }

        return nil
    }
}
