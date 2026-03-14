import Foundation

/// Normalized directions supported by Shellraiser split automation.
public enum ShellraiserSplitDirection: String, CaseIterable, Codable {
    case left
    case right
    case up
    case down
}

/// Stable details for one scriptable Shellraiser terminal surface.
public struct ShellraiserSurfaceSnapshot: Codable, Equatable {
    /// Stable application-level terminal identifier.
    public let id: String

    /// User-visible terminal title.
    public let title: String

    /// Current working directory reported by Shellraiser.
    public let workingDirectory: String

    /// Owning Shellraiser workspace identifier when known.
    public let workspaceId: String?

    /// Owning Shellraiser workspace name when known.
    public let workspaceName: String?

    /// Creates a snapshot value with explicit fields.
    public init(
        id: String,
        title: String,
        workingDirectory: String,
        workspaceId: String? = nil,
        workspaceName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
    }
}

/// Stable details for one scriptable Shellraiser workspace.
public struct ShellraiserWorkspaceSnapshot: Codable, Equatable {
    /// Stable workspace identifier.
    public let id: String

    /// User-visible workspace name.
    public let name: String

    /// Current selected terminal surface in the workspace when known.
    public let selectedSurfaceId: String?

    /// Creates a snapshot value with explicit fields.
    public init(id: String, name: String, selectedSurfaceId: String? = nil) {
        self.id = id
        self.name = name
        self.selectedSurfaceId = selectedSurfaceId
    }
}

/// Result returned after creating a new workspace through the control API.
public struct ShellraiserWorkspaceCreation: Codable, Equatable {
    /// Newly created workspace snapshot.
    public let workspace: ShellraiserWorkspaceSnapshot

    /// Starter terminal created inside the new workspace.
    public let surface: ShellraiserSurfaceSnapshot

    /// Creates a creation result from workspace and surface snapshots.
    public init(workspace: ShellraiserWorkspaceSnapshot, surface: ShellraiserSurfaceSnapshot) {
        self.workspace = workspace
        self.surface = surface
    }
}

/// Common failure type for Shellraiser CLI control and tmux compatibility flows.
public struct ShellraiserControlError: Error, CustomStringConvertible, Equatable {
    /// Human-readable failure description.
    public let message: String

    /// Creates a typed control error.
    public init(_ message: String) {
        self.message = message
    }

    /// Returns the user-facing failure description.
    public var description: String {
        message
    }
}

/// Structured command result used by CLI wrappers.
public struct ShellraiserCommandResult: Equatable {
    /// Process exit status.
    public let exitCode: Int32

    /// Text written to standard output.
    public let standardOutput: String

    /// Text written to standard error.
    public let standardError: String

    /// Creates a command result value.
    public init(exitCode: Int32 = 0, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Abstract Shellraiser control transport used by both native and tmux-compatible CLIs.
public protocol ShellraiserControlling {
    /// Creates a new workspace and returns the created workspace plus starter surface.
    func createWorkspace(name: String, workingDirectory: String?) throws -> ShellraiserWorkspaceCreation

    /// Splits the pane owning the supplied surface and returns the new sibling surface.
    func splitSurface(
        id: String,
        direction: ShellraiserSplitDirection,
        workingDirectory: String?
    ) throws -> ShellraiserSurfaceSnapshot

    /// Focuses one existing surface.
    func focusSurface(id: String) throws

    /// Sends literal text into one existing surface.
    func sendText(_ text: String, toSurfaceWithID id: String) throws

    /// Sends one named key into one existing surface.
    func sendKey(named keyName: String, toSurfaceWithID id: String) throws

    /// Returns all currently known workspaces.
    func listWorkspaces() throws -> [ShellraiserWorkspaceSnapshot]

    /// Returns all currently known surfaces, optionally scoped to one workspace.
    func listSurfaces(workspaceID: String?) throws -> [ShellraiserSurfaceSnapshot]

    /// Returns one surface snapshot when it still exists.
    func surface(withID id: String) throws -> ShellraiserSurfaceSnapshot?

    /// Closes one existing surface.
    func closeSurface(id: String) throws

    /// Closes one existing workspace.
    func closeWorkspace(id: String) throws
}
