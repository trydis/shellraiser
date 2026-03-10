import Foundation

/// Shared helpers for Shellraiser AppleScript commands.
@MainActor
private protocol TerminalTargetingScriptCommand: NSScriptCommand {}

extension TerminalTargetingScriptCommand {
    /// Resolves the destination terminal from the direct parameter, receiver, or `to` argument.
    func resolvedTerminal() -> ScriptableTerminal? {
        if let terminal = directParameter as? ScriptableTerminal {
            return terminal
        }

        if let terminals = directParameter as? [ScriptableTerminal], terminals.count == 1 {
            return terminals[0]
        }

        if let terminal = evaluatedReceivers as? ScriptableTerminal {
            return terminal
        }

        if let terminals = evaluatedReceivers as? [ScriptableTerminal], terminals.count == 1 {
            return terminals[0]
        }

        if let terminal = evaluatedArguments?["to"] as? ScriptableTerminal {
            return terminal
        }

        if let terminals = evaluatedArguments?["to"] as? [ScriptableTerminal], terminals.count == 1 {
            return terminals[0]
        }

        if let terminal = evaluatedArguments?["terminal"] as? ScriptableTerminal {
            return terminal
        }

        if let terminals = evaluatedArguments?["terminal"] as? [ScriptableTerminal], terminals.count == 1 {
            return terminals[0]
        }

        return nil
    }

    /// Records a standard AppleScript argument error and returns `nil`.
    func failArgument(_ message: String) -> Any? {
        scriptErrorNumber = NSArgumentsWrongScriptError
        scriptErrorString = message
        return nil
    }
}

/// Shared helpers for resolving optional surface configuration parameters.
@MainActor
private extension NSScriptCommand {
    /// Resolves the optional scripted surface configuration from supported parameter keys.
    func resolvedSurfaceConfiguration() -> ScriptableSurfaceConfiguration? {
        (evaluatedArguments?["configuration"] as? ScriptableSurfaceConfiguration)
            ?? (evaluatedArguments?["with configuration"] as? ScriptableSurfaceConfiguration)
            ?? (evaluatedArguments?["withConfiguration"] as? ScriptableSurfaceConfiguration)
    }

    /// Resolves the optional workspace name from supported scripting parameter keys.
    func resolvedWorkspaceName() -> String? {
        let name = (evaluatedArguments?["workspaceName"] as? String)
            ?? (evaluatedArguments?["named"] as? String)
            ?? (evaluatedArguments?["name"] as? String)
            ?? (directParameter as? String)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? nil : trimmedName
    }
}

/// Shared helpers for Shellraiser AppleScript split-direction decoding.
private enum ScriptSplitDirectionResolver {
    /// Resolves an AppleScript split direction argument into a normalized direction name.
    static func resolve(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        case let number as NSNumber:
            return resolve(code: UInt32(truncating: number))
        default:
            return nil
        }
    }

    /// Maps a four-character Apple event code to a direction string.
    private static func resolve(code: UInt32) -> String? {
        switch code {
        case fourCharacterCode("ShLf"):
            return "left"
        case fourCharacterCode("ShRt"):
            return "right"
        case fourCharacterCode("ShUp"):
            return "up"
        case fourCharacterCode("ShDn"):
            return "down"
        default:
            return nil
        }
    }

    /// Converts a four-character Apple event code into its integer representation.
    private static func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

/// AppleScript command that creates a new workspace.
@MainActor
@objc(NewWorkspaceScriptCommand)
final class NewWorkspaceScriptCommand: NSScriptCommand {
    /// Executes the `new workspace` command against the application scripting controller.
    override func performDefaultImplementation() -> Any? {
        let workspaceName = resolvedWorkspaceName()
        let configuration = resolvedSurfaceConfiguration()
        guard let workspace = ShellraiserScriptingController.shared.newWorkspace(
            name: workspaceName,
            configuration: configuration
        ) else {
            scriptErrorNumber = NSReceiverEvaluationScriptError
            scriptErrorString = "Shellraiser could not create the requested workspace."
            return nil
        }

        return workspace
    }
}

/// AppleScript command that creates a new surface configuration.
@MainActor
@objc(NewSurfaceConfigurationScriptCommand)
final class NewSurfaceConfigurationScriptCommand: NSScriptCommand {
    /// Executes the `new surface configuration` command against the application scripting controller.
    override func performDefaultImplementation() -> Any? {
        ShellraiserScriptingController.shared.newSurfaceConfiguration()
    }
}

/// AppleScript command that returns the number of open workspaces.
@MainActor
@objc(CountWorkspacesScriptCommand)
final class CountWorkspacesScriptCommand: NSScriptCommand {
    /// Executes the `count workspaces` command against the application scripting controller.
    override func performDefaultImplementation() -> Any? {
        NSNumber(value: ShellraiserScriptingController.shared.workspaces().count)
    }
}

/// AppleScript command that inputs literal text into a terminal surface.
@objc(InputTextScriptCommand)
final class InputTextScriptCommand: NSScriptCommand, TerminalTargetingScriptCommand {
    /// Executes the `input text` command against the resolved surface.
    override func performDefaultImplementation() -> Any? {
        let text = (directParameter as? String) ?? (evaluatedArguments?["text"] as? String)
        guard let text else {
            return failArgument("The input text command requires a text parameter.")
        }

        guard let terminal = resolvedTerminal() else {
            return failArgument("The input text command requires a terminal target.")
        }

        guard ShellraiserScriptingController.shared.input(text: text, to: terminal) else {
            scriptErrorNumber = NSReceiverEvaluationScriptError
            scriptErrorString = "Shellraiser could not find the requested terminal."
            return nil
        }

        return nil
    }
}

/// AppleScript command that splits the pane owning a specific terminal surface.
@objc(SplitTerminalScriptCommand)
final class SplitTerminalScriptCommand: NSScriptCommand, TerminalTargetingScriptCommand {
    /// Executes the `split terminal ...` command against the resolved surface.
    override func performDefaultImplementation() -> Any? {
        guard let terminal = resolvedTerminal() else {
            return failArgument("The split command requires a terminal.")
        }

        guard let direction = ScriptSplitDirectionResolver.resolve(evaluatedArguments?["direction"]) else {
            return failArgument("The split command requires a valid direction.")
        }
        let configuration = resolvedSurfaceConfiguration()

        guard let created = ShellraiserScriptingController.shared.split(
            terminal: terminal,
            direction: direction,
            configuration: configuration
        ) else {
            scriptErrorNumber = NSReceiverEvaluationScriptError
            scriptErrorString = "Shellraiser could not split the requested terminal."
            return nil
        }

        return created
    }
}

/// AppleScript command that sends a named control key into a terminal surface.
@objc(SendKeyScriptCommand)
final class SendKeyScriptCommand: NSScriptCommand, TerminalTargetingScriptCommand {
    /// Executes the `send key` command against the resolved surface.
    override func performDefaultImplementation() -> Any? {
        let keyName = (directParameter as? String) ?? (evaluatedArguments?["key"] as? String)
        guard let keyName else {
            return failArgument("The send key command requires a key name.")
        }

        guard let terminal = resolvedTerminal() else {
            return failArgument("The send key command requires a terminal target.")
        }

        guard ShellraiserScriptingController.shared.sendKey(named: keyName, to: terminal) else {
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = "Unsupported key name or missing terminal."
            return nil
        }

        return nil
    }
}

/// AppleScript command that focuses a specific terminal surface.
@objc(FocusTerminalScriptCommand)
final class FocusTerminalScriptCommand: NSScriptCommand, TerminalTargetingScriptCommand {
    /// Executes the `focus terminal` command against the resolved surface.
    override func performDefaultImplementation() -> Any? {
        guard let terminal = resolvedTerminal() else {
            return failArgument("The focus terminal command requires a terminal.")
        }

        guard ShellraiserScriptingController.shared.focus(terminal: terminal) else {
            scriptErrorNumber = NSReceiverEvaluationScriptError
            scriptErrorString = "Shellraiser could not focus the requested terminal."
            return nil
        }

        return nil
    }
}
