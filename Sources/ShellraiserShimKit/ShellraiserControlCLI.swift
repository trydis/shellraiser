import Foundation

/// Native Shellraiser control CLI that exposes a small, script-friendly automation surface.
public struct ShellraiserControlCLI {
    private let controller: ShellraiserControlling

    /// Creates a CLI wrapper around one control transport.
    public init(controller: ShellraiserControlling) {
        self.controller = controller
    }

    /// Parses and executes one `shellraiserctl` invocation.
    public func run(arguments: [String]) -> ShellraiserCommandResult {
        do {
            guard let command = arguments.first else {
                throw ShellraiserControlError(usageText)
            }

            switch command {
            case "new-workspace":
                return try runNewWorkspace(arguments: Array(arguments.dropFirst()))
            case "split":
                return try runSplit(arguments: Array(arguments.dropFirst()))
            case "focus-surface":
                return try runFocusSurface(arguments: Array(arguments.dropFirst()))
            case "send-text":
                return try runSendText(arguments: Array(arguments.dropFirst()))
            case "send-key":
                return try runSendKey(arguments: Array(arguments.dropFirst()))
            case "list-workspaces":
                return try runListWorkspaces()
            case "list-surfaces":
                return try runListSurfaces(arguments: Array(arguments.dropFirst()))
            case "get-surface":
                return try runGetSurface(arguments: Array(arguments.dropFirst()))
            case "close-surface":
                return try runCloseSurface(arguments: Array(arguments.dropFirst()))
            case "close-workspace":
                return try runCloseWorkspace(arguments: Array(arguments.dropFirst()))
            case "identify":
                return try runIdentify()
            case "help", "--help", "-h":
                return ShellraiserCommandResult(standardOutput: usageText + "\n")
            default:
                throw ShellraiserControlError("Unsupported shellraiserctl command: \(command)")
            }
        } catch {
            return ShellraiserCommandResult(exitCode: 1, standardError: "\(error)\n")
        }
    }

    /// Executes the `new-workspace` command.
    private func runNewWorkspace(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let name = parser.value(for: "--name") ?? "Workspace"
        let workingDirectory = parser.value(for: "--cwd")
        try parser.ensureFullyParsed()

        let created = try controller.createWorkspace(name: name, workingDirectory: workingDirectory)
        let output = [
            "workspace_id=\(created.workspace.id)",
            "workspace_name=\(created.workspace.name)",
            "surface_id=\(created.surface.id)",
            "surface_title=\(created.surface.title)",
            "surface_cwd=\(created.surface.workingDirectory)"
        ].joined(separator: "\n")

        return ShellraiserCommandResult(standardOutput: output + "\n")
    }

    /// Executes the `split` command.
    private func runSplit(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        let workingDirectory = parser.value(for: "--cwd")
        let directionName = try parser.requiredPositional("split direction")
        try parser.ensureFullyParsed()

        guard let direction = ShellraiserSplitDirection(rawValue: directionName) else {
            throw ShellraiserControlError("Unsupported split direction: \(directionName)")
        }

        let surface = try controller.splitSurface(id: surfaceID, direction: direction, workingDirectory: workingDirectory)
        let output = [
            "surface_id=\(surface.id)",
            "surface_title=\(surface.title)",
            "surface_cwd=\(surface.workingDirectory)"
        ].joined(separator: "\n")

        return ShellraiserCommandResult(standardOutput: output + "\n")
    }

    /// Executes the `focus-surface` command.
    private func runFocusSurface(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        try parser.ensureFullyParsed()
        try controller.focusSurface(id: surfaceID)
        return ShellraiserCommandResult()
    }

    /// Executes the `send-text` command.
    private func runSendText(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        let text = try parser.requiredPositional("text")
        try parser.ensureFullyParsed()
        try controller.sendText(text, toSurfaceWithID: surfaceID)
        return ShellraiserCommandResult()
    }

    /// Executes the `send-key` command.
    private func runSendKey(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        let keyName = try parser.requiredPositional("key")
        try parser.ensureFullyParsed()
        try controller.sendKey(named: keyName, toSurfaceWithID: surfaceID)
        return ShellraiserCommandResult()
    }

    /// Executes the `list-workspaces` command.
    private func runListWorkspaces() throws -> ShellraiserCommandResult {
        let output = try controller.listWorkspaces()
            .map { "\($0.id)\t\($0.name)\t\($0.selectedSurfaceId ?? "")" }
            .joined(separator: "\n")
        return ShellraiserCommandResult(standardOutput: output.isEmpty ? "" : output + "\n")
    }

    /// Executes the `list-surfaces` command.
    private func runListSurfaces(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let workspaceID = parser.value(for: "--workspace")
        try parser.ensureFullyParsed()

        let output = try controller.listSurfaces(workspaceID: workspaceID)
            .map { "\($0.id)\t\($0.title)\t\($0.workingDirectory)\t\($0.workspaceId ?? "")\t\($0.workspaceName ?? "")" }
            .joined(separator: "\n")
        return ShellraiserCommandResult(standardOutput: output.isEmpty ? "" : output + "\n")
    }

    /// Executes the `get-surface` command.
    private func runGetSurface(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        try parser.ensureFullyParsed()

        guard let surface = try controller.surface(withID: surfaceID) else {
            return ShellraiserCommandResult(exitCode: 1)
        }

        let output = [
            "surface_id=\(surface.id)",
            "surface_title=\(surface.title)",
            "surface_cwd=\(surface.workingDirectory)",
            "workspace_id=\(surface.workspaceId ?? "")",
            "workspace_name=\(surface.workspaceName ?? "")"
        ].joined(separator: "\n")
        return ShellraiserCommandResult(standardOutput: output + "\n")
    }

    /// Executes the `close-surface` command.
    private func runCloseSurface(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let surfaceID = try parser.requiredValue(for: "--surface")
        try parser.ensureFullyParsed()
        try controller.closeSurface(id: surfaceID)
        return ShellraiserCommandResult()
    }

    /// Executes the `close-workspace` command.
    private func runCloseWorkspace(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let workspaceID = try parser.requiredValue(for: "--workspace")
        try parser.ensureFullyParsed()
        try controller.closeWorkspace(id: workspaceID)
        return ShellraiserCommandResult()
    }

    /// Executes the `identify` command.
    private func runIdentify() throws -> ShellraiserCommandResult {
        let workspaces = try controller.listWorkspaces()
        let surfaces = try controller.listSurfaces(workspaceID: nil)
        let output = [
            "workspace_count=\(workspaces.count)",
            "surface_count=\(surfaces.count)"
        ].joined(separator: "\n")
        return ShellraiserCommandResult(standardOutput: output + "\n")
    }

    /// Returns top-level CLI usage text.
    private var usageText: String {
        """
        Usage: shellraiserctl <command> [options]

        Commands:
          new-workspace [--name <name>] [--cwd <path>]
          split --surface <id> <left|right|up|down> [--cwd <path>]
          focus-surface --surface <id>
          send-text --surface <id> <text>
          send-key --surface <id> <key>
          list-workspaces
          list-surfaces [--workspace <id>]
          get-surface --surface <id>
          close-surface --surface <id>
          close-workspace --workspace <id>
          identify
        """
    }
}

/// Minimal option parser used by the native and tmux-compatible CLIs.
struct CommandArgumentParser {
    private(set) var remaining: [String]

    /// Creates a parser over one argument vector.
    init(arguments: [String]) {
        self.remaining = arguments
    }

    /// Consumes one flag without an associated value.
    mutating func flag(_ name: String) -> Bool {
        guard let index = remaining.firstIndex(of: name) else { return false }
        remaining.remove(at: index)
        return true
    }

    /// Consumes one named option value when present.
    /// When the flag is the last token with no following value, the flag is still consumed
    /// to avoid leaving it in `remaining` and causing confusing "unexpected arguments" errors.
    mutating func value(for name: String) -> String? {
        guard let index = remaining.firstIndex(of: name) else { return nil }
        guard remaining.indices.contains(index + 1) else {
            remaining.remove(at: index)
            return nil
        }
        let value = remaining[index + 1]
        remaining.removeSubrange(index...(index + 1))
        return value
    }

    /// Consumes one required named option value.
    mutating func requiredValue(for name: String) throws -> String {
        guard let value = value(for: name), !value.isEmpty else {
            throw ShellraiserControlError("Missing value for \(name)")
        }
        return value
    }

    /// Consumes one positional argument.
    mutating func requiredPositional(_ label: String) throws -> String {
        guard let first = remaining.first else {
            throw ShellraiserControlError("Missing \(label)")
        }
        remaining.removeFirst()
        return first
    }

    /// Removes and returns all currently unparsed trailing arguments.
    mutating func drainRemaining() -> [String] {
        let drained = remaining
        remaining.removeAll()
        return drained
    }

    /// Ensures no unparsed arguments remain.
    mutating func ensureFullyParsed() throws {
        guard remaining.isEmpty else {
            throw ShellraiserControlError("Unexpected arguments: \(remaining.joined(separator: " "))")
        }
    }
}
