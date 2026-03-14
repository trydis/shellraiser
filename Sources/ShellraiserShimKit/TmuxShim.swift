import Foundation

/// Persistent pane registry stored for tmux-compatible Shellraiser sessions.
public struct TmuxShimState: Codable, Equatable {
    /// Schema version for future migrations.
    public var version: Int

    /// Next pane ordinal allocated by the shim.
    public var nextPaneOrdinal: Int

    /// All known sessions keyed by their tmux-visible names.
    public var sessionsByName: [String: TmuxShimSession]

    /// Creates an empty state value.
    public init(version: Int = 1, nextPaneOrdinal: Int = 1, sessionsByName: [String: TmuxShimSession] = [:]) {
        self.version = version
        self.nextPaneOrdinal = nextPaneOrdinal
        self.sessionsByName = sessionsByName
    }
}

/// One tmux-visible session tracked by the shim.
public struct TmuxShimSession: Codable, Equatable {
    /// tmux-visible session name.
    public var name: String

    /// Backing Shellraiser workspace identifier.
    public var workspaceId: String

    /// Ordered panes tracked for the session.
    public var panes: [TmuxShimPane]

    /// Currently focused pane identifier when known.
    public var focusedPaneId: String?

    /// Creates a session value from explicit fields.
    public init(name: String, workspaceId: String, panes: [TmuxShimPane], focusedPaneId: String?) {
        self.name = name
        self.workspaceId = workspaceId
        self.panes = panes
        self.focusedPaneId = focusedPaneId
    }
}

/// One tmux-visible pane tracked by the shim.
public struct TmuxShimPane: Codable, Equatable {
    /// tmux-style pane identifier such as `%1`.
    public var paneId: String

    /// Backing Shellraiser surface identifier.
    public var surfaceId: String

    /// Creates a pane value from explicit fields.
    public init(paneId: String, surfaceId: String) {
        self.paneId = paneId
        self.surfaceId = surfaceId
    }
}

/// State storage abstraction used by the tmux-compatible shim.
public protocol TmuxShimStateStoring {
    /// Loads the current persisted shim state.
    func load() throws -> TmuxShimState

    /// Persists the supplied shim state atomically.
    func save(_ state: TmuxShimState) throws
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
}

/// tmux-compatible command runner backed by native Shellraiser automation primitives.
public struct TmuxShimCLI {
    private let controller: ShellraiserControlling
    private let stateStore: TmuxShimStateStoring

    /// Creates a tmux-compatible CLI wrapper around one control transport and one state store.
    public init(controller: ShellraiserControlling, stateStore: TmuxShimStateStoring) {
        self.controller = controller
        self.stateStore = stateStore
    }

    /// Parses and executes one tmux-compatible invocation.
    public func run(arguments: [String]) -> ShellraiserCommandResult {
        do {
            guard let command = arguments.first else {
                throw ShellraiserControlError("tmux shim requires a command")
            }

            switch command {
            case "has-session":
                return try runHasSession(arguments: Array(arguments.dropFirst()))
            case "new-session":
                return try runNewSession(arguments: Array(arguments.dropFirst()))
            case "split-window":
                return try runSplitWindow(arguments: Array(arguments.dropFirst()))
            case "send-keys":
                return try runSendKeys(arguments: Array(arguments.dropFirst()))
            case "select-pane":
                return try runSelectPane(arguments: Array(arguments.dropFirst()))
            case "list-panes":
                return try runListPanes(arguments: Array(arguments.dropFirst()))
            case "display-message":
                return try runDisplayMessage(arguments: Array(arguments.dropFirst()))
            case "kill-pane":
                return try runKillPane(arguments: Array(arguments.dropFirst()))
            case "kill-session":
                return try runKillSession(arguments: Array(arguments.dropFirst()))
            default:
                throw ShellraiserControlError("Unsupported tmux command: \(command)")
            }
        } catch {
            return ShellraiserCommandResult(exitCode: 1, standardError: "\(error)\n")
        }
    }

    /// Executes `tmux has-session`.
    private func runHasSession(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let sessionName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        var state = try stateStore.load()
        let exists = try cleanupStaleEntries(in: &state).sessionsByName[sessionName] != nil
        try stateStore.save(state)
        return ShellraiserCommandResult(exitCode: exists ? 0 : 1)
    }

    /// Executes `tmux new-session`.
    private func runNewSession(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        _ = parser.flag("-d")
        let sessionName = try parser.requiredValue(for: "-s")
        let remainingArguments = parser.drainRemaining()
        let commandText = remainingArguments.isEmpty ? nil : remainingArguments.joined(separator: " ")

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        guard state.sessionsByName[sessionName] == nil else {
            throw ShellraiserControlError("Session already exists: \(sessionName)")
        }

        let created = try controller.createWorkspace(name: sessionName, workingDirectory: nil)
        let pane = TmuxShimPane(paneId: allocatePaneID(in: &state), surfaceId: created.surface.id)
        let session = TmuxShimSession(
            name: sessionName,
            workspaceId: created.workspace.id,
            panes: [pane],
            focusedPaneId: pane.paneId
        )
        state.sessionsByName[sessionName] = session
        try stateStore.save(state)

        if let commandText, !commandText.isEmpty {
            try controller.sendText(commandText, toSurfaceWithID: created.surface.id)
            try controller.sendKey(named: "enter", toSurfaceWithID: created.surface.id)
        }

        return ShellraiserCommandResult(standardOutput: "\(pane.paneId)\n")
    }

    /// Executes `tmux split-window`.
    private func runSplitWindow(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let isHorizontal = parser.flag("-h")
        let isVertical = parser.flag("-v")
        let remainingArguments = parser.drainRemaining()
        let commandText = remainingArguments.isEmpty ? nil : remainingArguments.joined(separator: " ")

        let direction: ShellraiserSplitDirection = isHorizontal ? .right : (isVertical ? .down : .down)

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolved = try resolveTarget(targetName, in: &state)
        let createdSurface = try controller.splitSurface(
            id: resolved.pane.surfaceId,
            direction: direction,
            workingDirectory: nil
        )

        guard var session = state.sessionsByName[resolved.session.name] else {
            throw ShellraiserControlError("Session disappeared during split.")
        }

        let pane = TmuxShimPane(paneId: allocatePaneID(in: &state), surfaceId: createdSurface.id)
        session.panes.append(pane)
        session.focusedPaneId = pane.paneId
        state.sessionsByName[session.name] = session
        try stateStore.save(state)

        if let commandText, !commandText.isEmpty {
            try controller.sendText(commandText, toSurfaceWithID: createdSurface.id)
            try controller.sendKey(named: "enter", toSurfaceWithID: createdSurface.id)
        }

        return ShellraiserCommandResult(standardOutput: "\(pane.paneId)\n")
    }

    /// Executes `tmux send-keys`.
    private func runSendKeys(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let literalMode = parser.flag("-l")
        let tokens = parser.drainRemaining()

        guard !tokens.isEmpty else {
            throw ShellraiserControlError("send-keys requires at least one key or text token")
        }

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolved = try resolveTarget(targetName, in: &state)
        try stateStore.save(state)

        if literalMode {
            try controller.sendText(tokens.joined(separator: " "), toSurfaceWithID: resolved.pane.surfaceId)
            return ShellraiserCommandResult()
        }

        try sendTokens(tokens, toSurfaceID: resolved.pane.surfaceId)
        return ShellraiserCommandResult()
    }

    /// Executes `tmux select-pane`.
    private func runSelectPane(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolved = try resolveTarget(targetName, in: &state)
        try controller.focusSurface(id: resolved.pane.surfaceId)

        guard var session = state.sessionsByName[resolved.session.name] else {
            throw ShellraiserControlError("Session disappeared during focus.")
        }
        session.focusedPaneId = resolved.pane.paneId
        state.sessionsByName[session.name] = session
        try stateStore.save(state)
        return ShellraiserCommandResult()
    }

    /// Executes `tmux list-panes`.
    private func runListPanes(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = parser.value(for: "-t")
        let format = parser.value(for: "-F") ?? "#{pane_id}"
        try parser.ensureFullyParsed()

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolvedSession = try resolveSession(targetName, in: &state)
        let lines = try renderPaneLines(for: resolvedSession, format: format)
        try stateStore.save(state)
        return ShellraiserCommandResult(standardOutput: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
    }

    /// Executes `tmux display-message`.
    private func runDisplayMessage(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        _ = parser.flag("-p")
        let targetName = parser.value(for: "-t")
        let format = try parser.requiredPositional("format")
        try parser.ensureFullyParsed()

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolved = try resolveTarget(targetName, in: &state)
        let line = try renderFormat(
            format,
            session: resolved.session,
            pane: resolved.pane,
            surface: controller.surface(withID: resolved.pane.surfaceId)
        )
        try stateStore.save(state)
        return ShellraiserCommandResult(standardOutput: line + "\n")
    }

    /// Executes `tmux kill-pane`.
    private func runKillPane(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let targetName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        let resolved = try resolveTarget(targetName, in: &state)
        try controller.closeSurface(id: resolved.pane.surfaceId)

        guard var session = state.sessionsByName[resolved.session.name] else {
            throw ShellraiserControlError("Session disappeared during pane close.")
        }
        session.panes.removeAll { $0.paneId == resolved.pane.paneId }
        session.focusedPaneId = session.panes.first?.paneId

        if session.panes.isEmpty {
            state.sessionsByName.removeValue(forKey: session.name)
        } else {
            state.sessionsByName[session.name] = session
        }

        try stateStore.save(state)
        return ShellraiserCommandResult()
    }

    /// Executes `tmux kill-session`.
    private func runKillSession(arguments: [String]) throws -> ShellraiserCommandResult {
        var parser = CommandArgumentParser(arguments: arguments)
        let sessionName = try parser.requiredValue(for: "-t")
        try parser.ensureFullyParsed()

        var state = try loadState()
        _ = try cleanupStaleEntries(in: &state)
        guard let session = state.sessionsByName.removeValue(forKey: sessionName) else {
            throw ShellraiserControlError("Unknown session: \(sessionName)")
        }
        try controller.closeWorkspace(id: session.workspaceId)
        try stateStore.save(state)
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
            guard token.count == 3 || token.count == 4 else { return nil }
            let normalized = token.lowercased().replacingOccurrences(of: "-", with: "")
            guard normalized.hasPrefix("c"), let letter = normalized.last, letter.isLetter else {
                return nil
            }
            return "ctrl-\(letter)"
        }
    }

    /// Renders one pane list for `list-panes`.
    private func renderPaneLines(for session: TmuxShimSession, format: String) throws -> [String] {
        try session.panes.map { pane in
            let surface = try controller.surface(withID: pane.surfaceId)
            return try renderFormat(format, session: session, pane: pane, surface: surface)
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
            .replacingOccurrences(of: "#{pane_current_path}", with: surface?.workingDirectory ?? "")
            .replacingOccurrences(of: "#{pane_title}", with: surface?.title ?? "")
            .replacingOccurrences(of: "#{window_active}", with: activeValue)
    }

    /// Loads the current shim state from storage.
    private func loadState() throws -> TmuxShimState {
        try stateStore.load()
    }

    /// Allocates the next tmux-visible pane identifier.
    private func allocatePaneID(in state: inout TmuxShimState) -> String {
        let paneID = "%\(state.nextPaneOrdinal)"
        state.nextPaneOrdinal += 1
        return paneID
    }

    /// Removes stale sessions and panes whose backing Shellraiser objects no longer exist.
    private func cleanupStaleEntries(in state: inout TmuxShimState) throws -> TmuxShimState {
        var cleaned = state
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

        state = cleaned
        return cleaned
    }

    /// Resolves one target string into a concrete session plus pane.
    private func resolveTarget(_ rawTarget: String?, in state: inout TmuxShimState) throws -> (session: TmuxShimSession, pane: TmuxShimPane) {
        if let rawTarget, rawTarget.contains(":%") {
            let pieces = rawTarget.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let sessionName = String(pieces[0])
            let paneID = String(pieces[1])
            guard let session = state.sessionsByName[sessionName],
                  let pane = session.panes.first(where: { $0.paneId == paneID }) else {
                throw ShellraiserControlError("Unknown pane target: \(rawTarget)")
            }
            return (session, pane)
        }

        if let rawTarget, rawTarget.hasPrefix("%") {
            for session in state.sessionsByName.values {
                if let pane = session.panes.first(where: { $0.paneId == rawTarget }) {
                    return (session, pane)
                }
            }
            throw ShellraiserControlError("Unknown pane target: \(rawTarget)")
        }

        let session = try resolveSession(rawTarget, in: &state)
        guard let focusedPaneID = session.focusedPaneId ?? session.panes.first?.paneId,
              let pane = session.panes.first(where: { $0.paneId == focusedPaneID }) else {
            throw ShellraiserControlError("No pane available for session: \(session.name)")
        }
        return (session, pane)
    }

    /// Resolves one target string into a concrete session.
    private func resolveSession(_ rawTarget: String?, in state: inout TmuxShimState) throws -> TmuxShimSession {
        if let rawTarget, !rawTarget.isEmpty {
            guard let session = state.sessionsByName[rawTarget] else {
                throw ShellraiserControlError("Unknown session: \(rawTarget)")
            }
            return session
        }

        guard state.sessionsByName.count == 1, let session = state.sessionsByName.values.first else {
            throw ShellraiserControlError("Target is required when more than one session exists")
        }
        return session
    }
}
