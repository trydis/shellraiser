import Foundation

/// Persistent pane registry stored for tmux-compatible Shellraiser sessions.
public struct TmuxShimState: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case version
        case nextPaneOrdinal
        case sessionsByName
        case socketsByName
    }

    /// Schema version for future migrations.
    public var version: Int

    /// Socket-scoped tmux state keyed by `tmux -L` namespace.
    public var socketsByName: [String: TmuxShimSocketState]

    /// Default socket name used when no `-L` flag is provided.
    public static let defaultSocketName = "default"

    /// Creates an empty state value.
    public init(
        version: Int = 1,
        nextPaneOrdinal: Int = 1,
        sessionsByName: [String: TmuxShimSession] = [:],
        socketsByName: [String: TmuxShimSocketState]? = nil
    ) {
        self.version = version
        if let socketsByName {
            self.socketsByName = socketsByName
        } else {
            self.socketsByName = [
                Self.defaultSocketName: TmuxShimSocketState(
                    nextPaneOrdinal: nextPaneOrdinal,
                    sessionsByName: sessionsByName
                )
            ]
        }
    }

    /// Decodes current socket-scoped state and migrates the older flat schema on read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        if let socketsByName = try container.decodeIfPresent([String: TmuxShimSocketState].self, forKey: .socketsByName) {
            self.socketsByName = socketsByName
            return
        }

        let nextPaneOrdinal = try container.decodeIfPresent(Int.self, forKey: .nextPaneOrdinal) ?? 1
        let sessionsByName = try container.decodeIfPresent([String: TmuxShimSession].self, forKey: .sessionsByName) ?? [:]
        self.socketsByName = [
            Self.defaultSocketName: TmuxShimSocketState(
                nextPaneOrdinal: nextPaneOrdinal,
                sessionsByName: sessionsByName
            )
        ]
    }

    /// Encodes the current socket-scoped state schema.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(socketsByName, forKey: .socketsByName)
    }

    /// Convenience view over the default socket used by existing tests and callers.
    public var nextPaneOrdinal: Int {
        get { socketState(named: Self.defaultSocketName).nextPaneOrdinal }
        set { setSocketState(socketState(named: Self.defaultSocketName).withNextPaneOrdinal(newValue), named: Self.defaultSocketName) }
    }

    /// Convenience view over default-socket sessions used by existing tests and callers.
    public var sessionsByName: [String: TmuxShimSession] {
        get { socketState(named: Self.defaultSocketName).sessionsByName }
        set { setSocketState(socketState(named: Self.defaultSocketName).withSessionsByName(newValue), named: Self.defaultSocketName) }
    }

    /// Returns one socket-scoped state value, synthesizing an empty namespace when missing.
    public func socketState(named socketName: String) -> TmuxShimSocketState {
        socketsByName[socketName] ?? TmuxShimSocketState()
    }

    /// Stores one socket-scoped state value, pruning empty sockets for compact persistence.
    public mutating func setSocketState(_ socketState: TmuxShimSocketState, named socketName: String) {
        if socketState.isEmpty {
            socketsByName.removeValue(forKey: socketName)
        } else {
            socketsByName[socketName] = socketState
        }
    }
}

/// One tmux socket namespace tracked by the shim.
public struct TmuxShimSocketState: Codable, Equatable {
    /// Next pane ordinal allocated by the shim.
    public var nextPaneOrdinal: Int

    /// All known sessions keyed by their tmux-visible names.
    public var sessionsByName: [String: TmuxShimSession]

    /// Creates one socket-scoped state value.
    public init(nextPaneOrdinal: Int = 1, sessionsByName: [String: TmuxShimSession] = [:]) {
        self.nextPaneOrdinal = nextPaneOrdinal
        self.sessionsByName = sessionsByName
    }

    /// Returns whether the namespace contains no tracked sessions and no advanced allocations.
    public var isEmpty: Bool {
        nextPaneOrdinal == 1 && sessionsByName.isEmpty
    }

    /// Returns a copy with an updated pane ordinal.
    public func withNextPaneOrdinal(_ nextPaneOrdinal: Int) -> TmuxShimSocketState {
        var copy = self
        copy.nextPaneOrdinal = nextPaneOrdinal
        return copy
    }

    /// Returns a copy with updated sessions.
    public func withSessionsByName(_ sessionsByName: [String: TmuxShimSession]) -> TmuxShimSocketState {
        var copy = self
        copy.sessionsByName = sessionsByName
        return copy
    }
}

/// One tmux-visible session tracked by the shim.
public struct TmuxShimSession: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case name
        case workspaceId
        case panes
        case focusedPaneId
        case ownsWorkspace
    }

    /// tmux-visible session name.
    public var name: String

    /// Backing Shellraiser workspace identifier.
    public var workspaceId: String

    /// Ordered panes tracked for the session.
    public var panes: [TmuxShimPane]

    /// Currently focused pane identifier when known.
    public var focusedPaneId: String?

    /// Whether this shim session owns the backing workspace lifecycle.
    public var ownsWorkspace: Bool

    /// Creates a session value from explicit fields.
    public init(
        name: String,
        workspaceId: String,
        panes: [TmuxShimPane],
        focusedPaneId: String?,
        ownsWorkspace: Bool = true
    ) {
        self.name = name
        self.workspaceId = workspaceId
        self.panes = panes
        self.focusedPaneId = focusedPaneId
        self.ownsWorkspace = ownsWorkspace
    }

    /// Decodes sessions while defaulting older state files to workspace-owned behavior.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        panes = try container.decode([TmuxShimPane].self, forKey: .panes)
        focusedPaneId = try container.decodeIfPresent(String.self, forKey: .focusedPaneId)
        ownsWorkspace = try container.decodeIfPresent(Bool.self, forKey: .ownsWorkspace) ?? true
    }

    /// Encodes sessions with explicit workspace ownership.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(workspaceId, forKey: .workspaceId)
        try container.encode(panes, forKey: .panes)
        try container.encodeIfPresent(focusedPaneId, forKey: .focusedPaneId)
        try container.encode(ownsWorkspace, forKey: .ownsWorkspace)
    }
}

/// One tmux-visible pane tracked by the shim.
public struct TmuxShimPane: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case paneId
        case surfaceId
        case windowName
    }

    /// tmux-style pane identifier such as `%1`.
    public var paneId: String

    /// Backing Shellraiser surface identifier.
    public var surfaceId: String

    /// tmux-visible window name owning this pane.
    public var windowName: String

    /// Creates a pane value from explicit fields.
    public init(paneId: String, surfaceId: String, windowName: String = "main") {
        self.paneId = paneId
        self.surfaceId = surfaceId
        self.windowName = windowName
    }

    /// Decodes pane state while defaulting older state files to the main window name.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneId = try container.decode(String.self, forKey: .paneId)
        surfaceId = try container.decode(String.self, forKey: .surfaceId)
        windowName = try container.decodeIfPresent(String.self, forKey: .windowName) ?? "main"
    }

    /// Encodes pane state with explicit window names.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paneId, forKey: .paneId)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encode(windowName, forKey: .windowName)
    }
}

/// State storage abstraction used by the tmux-compatible shim.
public protocol TmuxShimStateStoring {
    /// Loads the current persisted shim state.
    func load() throws -> TmuxShimState

    /// Persists the supplied shim state atomically.
    func save(_ state: TmuxShimState) throws

    /// Loads state, passes it to body for in-place modification, then saves — all under an
    /// exclusive advisory lock so concurrent shim invocations cannot interleave their
    /// load–modify–save cycles.
    func transact(_ body: (inout TmuxShimState) throws -> Void) throws
}

/// File-backed state store for the tmux-compatible shim.
public struct FileTmuxShimStateStore: TmuxShimStateStoring {
    private let stateURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileManager: FileManager

    /// Creates a file-backed state store rooted at the default per-user location.
    public init(
        stateURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let stateURL {
            self.stateURL = stateURL
        } else {
            self.stateURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".shellraiser", isDirectory: true)
                .appendingPathComponent("tmux-shim-state.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Loads the current persisted shim state or returns an empty state when none exists.
    public func load() throws -> TmuxShimState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return TmuxShimState()
        }
        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(TmuxShimState.self, from: data)
    }

    /// Persists the supplied shim state atomically.
    public func save(_ state: TmuxShimState) throws {
        let directoryURL = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    /// Executes body under an exclusive `flock` advisory lock so concurrent shim processes
    /// cannot interleave their load–modify–save cycles. The lock file is a sibling of the
    /// state file. If the lock file cannot be opened, the body is executed without a lock.
    public func transact(_ body: (inout TmuxShimState) throws -> Void) throws {
        let directoryURL = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let lockPath = directoryURL.appendingPathComponent(".tmux-shim.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        if fd >= 0 { flock(fd, LOCK_EX) }
        var state = try load()
        try body(&state)
        try save(state)
    }
}

/// tmux-compatible command runner backed by native Shellraiser automation primitives.
public struct TmuxShimCLI {
    private let controller: ShellraiserControlling
    private let stateStore: TmuxShimStateStoring
    private let environment: [String: String]

    /// Creates a tmux-compatible CLI wrapper around one control transport and one state store.
    /// - Parameter environment: Process environment used for surface-binding lookups;
    ///   defaults to `ProcessInfo.processInfo.environment`.
    public init(
        controller: ShellraiserControlling,
        stateStore: TmuxShimStateStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.controller = controller
        self.stateStore = stateStore
        self.environment = environment
    }

    /// Parses and executes one tmux-compatible invocation.
    public func run(arguments: [String]) -> ShellraiserCommandResult {
        do {
            let parsedInvocation = try parseInvocation(arguments: arguments)
            let command = parsedInvocation.command

            guard let command else {
                throw ShellraiserControlError("tmux shim requires a command")
            }

            switch command {
            case "__version__":
                return runVersion()
            case "has-session":
                return try runHasSession(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "new-session":
                return try runNewSession(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "split-window":
                return try runSplitWindow(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "send-keys":
                return try runSendKeys(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "select-pane":
                return try runSelectPane(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "select-layout":
                return try runSelectLayout(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "list-panes":
                return try runListPanes(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "list-windows":
                return try runListWindows(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "new-window":
                return try runNewWindow(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "set-option":
                return try runSetOption(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "kill-pane":
                return try runKillPane(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            case "kill-session":
                return try runKillSession(arguments: parsedInvocation.arguments, socketName: parsedInvocation.socketName)
            default:
                throw ShellraiserControlError("Unsupported tmux command: \(command)")
            }
        } catch {
            return ShellraiserCommandResult(exitCode: 1, standardError: "\(error)\n")
        }
    }

    /// Emits a tmux-like version string for compatibility probes.
    private func runVersion() -> ShellraiserCommandResult {
        ShellraiserCommandResult(standardOutput: "tmux 3.4\n")
    }

    /// Parses one invocation, extracting supported global tmux flags before the command name.
    private func parseInvocation(arguments: [String]) throws -> (socketName: String, command: String?, arguments: [String]) {
        var remaining = arguments
        var socketName = TmuxShimState.defaultSocketName

        while let first = remaining.first, first.hasPrefix("-") {
            switch first {
            case "-L":
                guard remaining.count >= 2 else {
                    throw ShellraiserControlError("tmux shim requires a socket name after -L")
                }
                socketName = remaining[1]
                remaining.removeFirst(2)
            case "-V", "--version":
                remaining.removeFirst()
                return (socketName, "__version__", [])
            default:
                return (socketName, remaining.first, Array(remaining.dropFirst()))
            }
        }

        return (socketName, remaining.first, Array(remaining.dropFirst()))
    }

    /// Executes `tmux has-session`.
    private func runHasSession(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let sessionName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        var exists = false
        try stateStore.transact { state in
            exists = try cleanupStaleEntries(in: &state, socketName: socketName).sessionsByName[sessionName] != nil
        }
        return ShellraiserCommandResult(exitCode: exists ? 0 : 1)
    }

    /// Executes `tmux new-session`.
    private func runNewSession(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        _ = parser.flag("-d")
        _ = parser.flag("-P")
        let sessionName = try parser.requiredValue(for: "-s")
        let windowName = parser.value(for: "-n") ?? "main"
        let outputFormat = parser.value(for: "-F") ?? "#{pane_id}"
        let remainingArguments = parser.drainRemaining()
        let commandText = remainingArguments.isEmpty ? nil : remainingArguments.joined(separator: " ")

        var outputLine = ""
        try stateStore.transact { state in
            var socketState = try cleanupStaleEntries(in: &state, socketName: socketName)
            guard socketState.sessionsByName[sessionName] == nil else {
                throw ShellraiserControlError("Session already exists: \(sessionName)")
            }

            let created = try createSessionSurface(for: sessionName)
            let pane = TmuxShimPane(
                paneId: allocatePaneID(in: &socketState),
                surfaceId: created.surface.id,
                windowName: windowName
            )
            let session = TmuxShimSession(
                name: sessionName,
                workspaceId: created.workspace.id,
                panes: [pane],
                focusedPaneId: pane.paneId,
                ownsWorkspace: created.ownsWorkspace
            )
            socketState.sessionsByName[sessionName] = session
            state.setSocketState(socketState, named: socketName)

            if let commandText, !commandText.isEmpty {
                try controller.sendText(commandText, toSurfaceWithID: created.surface.id)
                try controller.sendKey(named: "enter", toSurfaceWithID: created.surface.id)
            }

            outputLine = try renderFormat(
                outputFormat,
                session: session,
                pane: pane,
                surface: created.surface
            )
        }
        return ShellraiserCommandResult(standardOutput: outputLine + "\n")
    }

    /// Creates the first teammate surface for one tmux session, attaching to the current workspace when possible.
    private func createSessionSurface(for sessionName: String) throws -> (
        workspace: ShellraiserWorkspaceSnapshot,
        surface: ShellraiserSurfaceSnapshot,
        ownsWorkspace: Bool
    ) {
        if let attached = try attachedWorkspaceCreationContext() {
            return attached
        }

        let created = try controller.createWorkspace(name: sessionName, workingDirectory: nil)
        return (created.workspace, created.surface, true)
    }

    /// Returns one workspace-attached creation context when the shim is invoked from a managed Shellraiser surface.
    private func attachedWorkspaceCreationContext() throws -> (
        workspace: ShellraiserWorkspaceSnapshot,
        surface: ShellraiserSurfaceSnapshot,
        ownsWorkspace: Bool
    )? {
        guard let rawSurfaceID = environment["SHELLRAISER_SURFACE_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSurfaceID.isEmpty,
              let originSurface = try controller.surface(withID: rawSurfaceID),
              let workspaceID = originSurface.workspaceId else {
            return nil
        }

        let workspaceName = originSurface.workspaceName ?? "Workspace"
        let workspace = ShellraiserWorkspaceSnapshot(
            id: workspaceID,
            name: workspaceName,
            selectedSurfaceId: originSurface.id
        )
        let createdSurface = try controller.splitSurface(
            id: originSurface.id,
            direction: .right,
            workingDirectory: nil
        )
        let normalizedSurface = ShellraiserSurfaceSnapshot(
            id: createdSurface.id,
            title: createdSurface.title,
            workingDirectory: createdSurface.workingDirectory,
            workspaceId: createdSurface.workspaceId ?? workspaceID,
            workspaceName: createdSurface.workspaceName ?? workspaceName
        )
        return (workspace, normalizedSurface, false)
    }

    /// Executes `tmux split-window`.
    private func runSplitWindow(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let isHorizontal = parser.flag("-h")
        let isVertical = parser.flag("-v")
        _ = parser.flag("-P")
        let outputFormat = parser.value(for: "-F") ?? "#{pane_id}"
        let workingDirectory = parser.value(for: "-c")
        let remainingArguments = parser.drainRemaining()
        let commandText = remainingArguments.isEmpty ? nil : remainingArguments.joined(separator: " ")

        let direction: ShellraiserSplitDirection = isHorizontal ? .right : (isVertical ? .down : .down)

        var outputLine = ""
        try stateStore.transact { state in
            var socketState = state.socketState(named: socketName)
            let resolved = try resolveTarget(targetName, in: socketState)
            let createdSurface = try controller.splitSurface(
                id: resolved.pane.surfaceId,
                direction: direction,
                workingDirectory: workingDirectory
            )

            guard var session = socketState.sessionsByName[resolved.session.name] else {
                throw ShellraiserControlError("Session disappeared during split.")
            }

            let pane = TmuxShimPane(
                paneId: allocatePaneID(in: &socketState),
                surfaceId: createdSurface.id,
                windowName: resolved.pane.windowName
            )
            session.panes.append(pane)
            session.focusedPaneId = pane.paneId
            socketState.sessionsByName[session.name] = session
            state.setSocketState(socketState, named: socketName)

            if let commandText, !commandText.isEmpty {
                try controller.sendText(commandText, toSurfaceWithID: createdSurface.id)
                try controller.sendKey(named: "enter", toSurfaceWithID: createdSurface.id)
            }

            outputLine = try renderFormat(
                outputFormat,
                session: session,
                pane: pane,
                surface: createdSurface
            )
        }
        return ShellraiserCommandResult(standardOutput: outputLine + "\n")
    }

    /// Executes `tmux send-keys`.
    private func runSendKeys(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let literalMode = parser.flag("-l")
        let tokens = parser.drainRemaining()

        guard !tokens.isEmpty else {
            throw ShellraiserControlError("send-keys requires at least one key or text token")
        }

        try stateStore.transact { state in
            let socketState = state.socketState(named: socketName)
            let resolved = try resolveTarget(targetName, in: socketState)

            if literalMode {
                try controller.sendText(tokens.joined(separator: " "), toSurfaceWithID: resolved.pane.surfaceId)
            } else {
                try sendTokens(tokens, toSurfaceID: resolved.pane.surfaceId)
            }
        }
        return ShellraiserCommandResult()
    }

    /// Executes `tmux select-pane`.
    private func runSelectPane(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = try parser.requiredValue(for: "-t")
        _ = parser.flag("-P")
        _ = parser.value(for: "-T")
        _ = parser.drainRemaining()

        try stateStore.transact { state in
            var socketState = state.socketState(named: socketName)
            let resolved = try resolveTarget(targetName, in: socketState)
            try controller.focusSurface(id: resolved.pane.surfaceId)

            guard var session = socketState.sessionsByName[resolved.session.name] else {
                throw ShellraiserControlError("Session disappeared during focus.")
            }
            session.focusedPaneId = resolved.pane.paneId
            socketState.sessionsByName[session.name] = session
            state.setSocketState(socketState, named: socketName)
        }
        return ShellraiserCommandResult()
    }

    /// Executes `tmux select-layout`.
    private func runSelectLayout(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        _ = try parser.requiredPositional("layout")
        try parser.ensureFullyParsed()

        try stateStore.transact { state in
            let socketState = state.socketState(named: socketName)
            _ = try resolveTarget(targetName, in: socketState)
        }
        return ShellraiserCommandResult()
    }

    /// Executes `tmux list-panes`.
    private func runListPanes(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let format = parser.value(for: "-F") ?? "#{pane_id}"
        try parser.ensureFullyParsed()

        var lines: [String] = []
        try stateStore.transact { state in
            let socketState = try cleanupStaleEntries(in: &state, socketName: socketName)
            let resolvedSession = try resolveSession(targetName, in: socketState)
            lines = try renderPaneLines(
                for: resolvedSession,
                format: format,
                windowName: sessionWindowName(from: targetName)
            )
            state.setSocketState(socketState, named: socketName)
        }
        return ShellraiserCommandResult(standardOutput: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
    }

    /// Executes `tmux list-windows`.
    private func runListWindows(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let format = parser.value(for: "-F") ?? "#{window_name}"
        try parser.ensureFullyParsed()

        var lines: [String] = []
        try stateStore.transact { state in
            let socketState = try cleanupStaleEntries(in: &state, socketName: socketName)
            let resolvedSession = try resolveSession(targetName, in: socketState)
            lines = renderWindowLines(for: resolvedSession, format: format)
            state.setSocketState(socketState, named: socketName)
        }
        return ShellraiserCommandResult(standardOutput: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
    }

    /// Executes `tmux new-window`.
    private func runNewWindow(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let windowName = parser.value(for: "-n") ?? "main"
        _ = parser.flag("-P")
        let outputFormat = parser.value(for: "-F") ?? "#{pane_id}"
        let workingDirectory = parser.value(for: "-c")
        let remainingArguments = parser.drainRemaining()
        let commandText = remainingArguments.isEmpty ? nil : remainingArguments.joined(separator: " ")

        var outputLine = ""
        try stateStore.transact { state in
            var socketState = state.socketState(named: socketName)
            let resolved = try resolveTarget(targetName, in: socketState)
            let createdSurface = try controller.splitSurface(
                id: resolved.pane.surfaceId,
                direction: .right,
                workingDirectory: workingDirectory
            )

            guard var session = socketState.sessionsByName[resolved.session.name] else {
                throw ShellraiserControlError("Session disappeared during window creation.")
            }

            let pane = TmuxShimPane(
                paneId: allocatePaneID(in: &socketState),
                surfaceId: createdSurface.id,
                windowName: windowName
            )
            session.panes.append(pane)
            session.focusedPaneId = pane.paneId
            socketState.sessionsByName[session.name] = session
            state.setSocketState(socketState, named: socketName)

            if let commandText, !commandText.isEmpty {
                try controller.sendText(commandText, toSurfaceWithID: createdSurface.id)
                try controller.sendKey(named: "enter", toSurfaceWithID: createdSurface.id)
            }

            outputLine = try renderFormat(
                outputFormat,
                session: session,
                pane: pane,
                surface: createdSurface
            )
        }
        return ShellraiserCommandResult(standardOutput: outputLine + "\n")
    }

    /// Executes `tmux set-option` as a no-op compatibility command for styling/layout tweaks.
    private func runSetOption(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        _ = parser.flag("-p")
        let targetName = parser.value(for: "-t")
        _ = parser.drainRemaining()

        try stateStore.transact { state in
            let socketState = state.socketState(named: socketName)
            if let targetName {
                if targetName.hasPrefix("%") || targetName.contains(":") {
                    _ = try resolveTarget(targetName, in: socketState)
                } else {
                    _ = try resolveSession(targetName, in: socketState)
                }
            }
        }
        return ShellraiserCommandResult()
    }

    /// Executes `tmux kill-pane`.
    private func runKillPane(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        try stateStore.transact { state in
            var socketState = try cleanupStaleEntries(in: &state, socketName: socketName)
            let resolved = try resolveTarget(targetName, in: socketState)
            try controller.closeSurface(id: resolved.pane.surfaceId)

            guard var session = socketState.sessionsByName[resolved.session.name] else {
                throw ShellraiserControlError("Session disappeared during pane close.")
            }
            session.panes.removeAll { $0.paneId == resolved.pane.paneId }
            session.focusedPaneId = session.panes.first?.paneId

            if session.panes.isEmpty {
                socketState.sessionsByName.removeValue(forKey: session.name)
            } else {
                socketState.sessionsByName[session.name] = session
            }

            state.setSocketState(socketState, named: socketName)
        }
        return ShellraiserCommandResult()
    }

    /// Executes `tmux kill-session`.
    private func runKillSession(arguments: [String], socketName: String) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let sessionName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        try stateStore.transact { state in
            var socketState = try cleanupStaleEntries(in: &state, socketName: socketName)
            guard let session = socketState.sessionsByName.removeValue(forKey: sessionName) else {
                throw ShellraiserControlError("Unknown session: \(sessionName)")
            }

            if session.ownsWorkspace {
                try controller.closeWorkspace(id: session.workspaceId)
            } else {
                for pane in session.panes {
                    try controller.closeSurface(id: pane.surfaceId)
                }
            }

            state.setSocketState(socketState, named: socketName)
        }
        return ShellraiserCommandResult()
    }

    /// Sends a mixed sequence of text tokens and special keys into one surface.
    private func sendTokens(_ tokens: [String], toSurfaceID surfaceID: String) throws {
        var pendingText: [String] = []

        func flushPendingText() throws {
            guard !pendingText.isEmpty else { return }
            try controller.sendText(pendingText.joined(separator: " "), toSurfaceWithID: surfaceID)
            pendingText.removeAll()
        }

        for token in tokens {
            if let keyName = normalizeKeyToken(token) {
                try flushPendingText()
                try controller.sendKey(named: keyName, toSurfaceWithID: surfaceID)
            } else {
                pendingText.append(token)
            }
        }

        try flushPendingText()
    }

    /// Normalizes one tmux `send-keys` token into a Shellraiser named key.
    private func normalizeKeyToken(_ token: String) -> String? {
        switch token.lowercased() {
        case "enter", "return":
            return "enter"
        case "tab":
            return "tab"
        case "escape", "esc":
            return "escape"
        case "bspace", "backspace", "delete":
            return "backspace"
        default:
            return controlLetterKey(from: token)
        }
    }

    /// Parses `C-x`, `ctrl-x`, and `ctrl+x` forms into a `ctrl-x` key name.
    private func controlLetterKey(from token: String) -> String? {
        let lower = token.lowercased()
        let rest: Substring
        if lower.hasPrefix("ctrl-") || lower.hasPrefix("ctrl+") {
            rest = lower.dropFirst(5)
        } else if lower.hasPrefix("c-") {
            rest = lower.dropFirst(2)
        } else {
            return nil
        }
        guard rest.count == 1, let letter = rest.first, letter.isLetter else {
            return nil
        }
        return "ctrl-\(letter)"
    }

    /// Renders one pane list for `list-panes`, batching surface lookups into a single controller call.
    private func renderPaneLines(for session: TmuxShimSession, format: String, windowName: String? = nil) throws -> [String] {
        let panes = session.panes.filter { windowName == nil || $0.windowName == windowName }
        guard !panes.isEmpty else { return [] }

        let allSurfaces = try controller.listSurfaces(workspaceID: nil)
        let surfaceByID = Dictionary(uniqueKeysWithValues: allSurfaces.map { ($0.id, $0) })

        return try panes.map { pane in
            try renderFormat(format, session: session, pane: pane, surface: surfaceByID[pane.surfaceId])
        }
    }

    /// Renders one window list for `list-windows`.
    private func renderWindowLines(for session: TmuxShimSession, format: String) -> [String] {
        var seenWindowNames = Set<String>()
        return session.panes.compactMap { pane in
            guard seenWindowNames.insert(pane.windowName).inserted else { return nil }
            return format.replacingOccurrences(of: "#{window_name}", with: pane.windowName)
        }
    }

    /// Expands the small supported format-token subset.
    private func renderFormat(
        _ format: String,
        session: TmuxShimSession,
        pane: TmuxShimPane,
        surface: ShellraiserSurfaceSnapshot?
    ) throws -> String {
        let activeValue = session.focusedPaneId == pane.paneId ? "1" : "0"
        return format
            .replacingOccurrences(of: "#{pane_id}", with: pane.paneId)
            .replacingOccurrences(of: "#{session_name}", with: session.name)
            .replacingOccurrences(of: "#{window_name}", with: pane.windowName)
            .replacingOccurrences(of: "#{pane_current_path}", with: surface?.workingDirectory ?? "")
            .replacingOccurrences(of: "#{pane_title}", with: surface?.title ?? "")
            .replacingOccurrences(of: "#{window_active}", with: activeValue)
    }

    /// Allocates the next tmux-visible pane identifier.
    private func allocatePaneID(in socketState: inout TmuxShimSocketState) -> String {
        let paneID = "%\(socketState.nextPaneOrdinal)"
        socketState.nextPaneOrdinal += 1
        return paneID
    }

    /// Removes stale sessions and panes whose backing Shellraiser objects no longer exist.
    private func cleanupStaleEntries(in state: inout TmuxShimState, socketName: String) throws -> TmuxShimSocketState {
        var cleaned = state.socketState(named: socketName)
        let workspaces = try controller.listWorkspaces()
        let surfaces = try controller.listSurfaces(workspaceID: nil)
        let workspaceIDs = Set(workspaces.map(\.id))
        let surfaceIDs = Set(surfaces.map(\.id))

        for (name, session) in cleaned.sessionsByName {
            guard workspaceIDs.contains(session.workspaceId) else {
                cleaned.sessionsByName.removeValue(forKey: name)
                continue
            }

            var nextSession = session
            nextSession.panes.removeAll { !surfaceIDs.contains($0.surfaceId) }
            nextSession.focusedPaneId = nextSession.panes.contains(where: { $0.paneId == nextSession.focusedPaneId })
                ? nextSession.focusedPaneId
                : nextSession.panes.first?.paneId

            if nextSession.panes.isEmpty {
                cleaned.sessionsByName.removeValue(forKey: name)
            } else {
                cleaned.sessionsByName[name] = nextSession
            }
        }

        state.setSocketState(cleaned, named: socketName)
        return cleaned
    }

    /// Resolves one target string into a concrete session plus pane.
    private func resolveTarget(_ rawTarget: String?, in socketState: TmuxShimSocketState) throws -> (session: TmuxShimSession, pane: TmuxShimPane) {
        if let rawTarget, rawTarget.contains(":%") {
            let pieces = rawTarget.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let sessionName = String(pieces[0])
            let paneID = String(pieces[1])
            guard let session = socketState.sessionsByName[sessionName],
                  let pane = session.panes.first(where: { $0.paneId == paneID }) else {
                throw ShellraiserControlError("Unknown pane target: \(rawTarget)")
            }
            return (session, pane)
        }

        if let rawTarget, rawTarget.hasPrefix("%") {
            for session in socketState.sessionsByName.values {
                if let pane = session.panes.first(where: { $0.paneId == rawTarget }) {
                    return (session, pane)
                }
            }
            throw ShellraiserControlError("Unknown pane target: \(rawTarget)")
        }

        if let rawTarget, rawTarget.contains(":") {
            let pieces = rawTarget.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let sessionName = String(pieces[0])
            let windowName = String(pieces[1])
            guard let session = socketState.sessionsByName[sessionName] else {
                throw ShellraiserControlError("Unknown session: \(sessionName)")
            }
            if let focusedPaneID = session.focusedPaneId,
               let pane = session.panes.first(where: { $0.paneId == focusedPaneID && $0.windowName == windowName }) {
                return (session, pane)
            }
            guard let pane = session.panes.first(where: { $0.windowName == windowName }) else {
                throw ShellraiserControlError("Unknown window target: \(rawTarget)")
            }
            return (session, pane)
        }

        let session = try resolveSession(rawTarget, in: socketState)
        guard let focusedPaneID = session.focusedPaneId ?? session.panes.first?.paneId,
              let pane = session.panes.first(where: { $0.paneId == focusedPaneID }) else {
            throw ShellraiserControlError("No pane available for session: \(session.name)")
        }
        return (session, pane)
    }

    /// Resolves one target string into a concrete session.
    private func resolveSession(_ rawTarget: String?, in socketState: TmuxShimSocketState) throws -> TmuxShimSession {
        if let rawTarget, !rawTarget.isEmpty {
            let sessionName = rawTarget.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .map(String.init)
                .first ?? rawTarget
            guard let session = socketState.sessionsByName[sessionName] else {
                throw ShellraiserControlError("Unknown session: \(rawTarget)")
            }
            return session
        }

        guard socketState.sessionsByName.count == 1, let session = socketState.sessionsByName.values.first else {
            throw ShellraiserControlError("Target is required when more than one session exists")
        }
        return session
    }

    /// Extracts one optional tmux window target from `session:window` references.
    private func sessionWindowName(from rawTarget: String?) -> String? {
        guard let rawTarget, rawTarget.contains(":"), !rawTarget.contains(":%") else {
            return nil
        }
        let pieces = rawTarget.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        return String(pieces[1])
    }
}
