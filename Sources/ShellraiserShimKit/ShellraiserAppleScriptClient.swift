import Foundation

/// Runs AppleScript through the `osascript` command-line tool.
public protocol AppleScriptRunning {
    /// Executes AppleScript source with positional arguments and returns standard output.
    func run(script: String, arguments: [String]) throws -> String
}

/// Default AppleScript runner backed by `/usr/bin/osascript`.
public struct OsaScriptRunner: AppleScriptRunning {
    /// Creates a default runner.
    public init() {}

    /// Executes AppleScript source through `osascript` and returns trimmed standard output.
    public func run(script: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()

        if let data = script.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        // Read output before waitUntilExit to avoid a deadlock: if the subprocess fills
        // the pipe buffer before exiting it blocks on write, which prevents it from
        // exiting, which prevents waitUntilExit from returning.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ShellraiserControlError(
                error.isEmpty ? "AppleScript execution failed." : error
            )
        }

        return output
    }
}

/// Shellraiser control client that drives the running app through AppleScript automation.
public struct ShellraiserAppleScriptClient: ShellraiserControlling {
    /// Field separator used when encoding records through AppleScript.
    static let fieldSeparator = "\u{1F}"

    /// Record separator used when encoding record lists through AppleScript.
    static let recordSeparator = "\u{1E}"

    private let runner: AppleScriptRunning
    private let applicationName: String

    /// Creates a Shellraiser control client with a pluggable AppleScript runner.
    public init(
        runner: AppleScriptRunning = OsaScriptRunner(),
        applicationName: String = "Shellraiser"
    ) {
        self.runner = runner
        self.applicationName = applicationName
    }

    /// Creates a new workspace through Shellraiser scripting.
    public func createWorkspace(name: String, workingDirectory: String?) throws -> ShellraiserWorkspaceCreation {
        let output = try runScript(
            script: """
            on run argv
                set workspaceName to item 1 of argv
                set cwdText to item 2 of argv
                set us to ASCII character 31

                tell application applicationName
                    set config to new surface configuration
                    if cwdText is not "" then
                        set initial working directory of config to cwdText
                    end if
                    set ws to new workspace named workspaceName with configuration config
                    set term to first terminal of selected tab of ws
                    return (id of ws) & us & (name of ws) & us & (id of term) & us & (title of term) & us & (working directory of term)
                end tell
            end run
            """,
            arguments: [name, workingDirectory ?? ""]
        )

        let fields = parseFields(output, expectedCount: 5)
        let workspace = ShellraiserWorkspaceSnapshot(
            id: fields[0],
            name: fields[1],
            selectedSurfaceId: fields[2]
        )
        let surface = ShellraiserSurfaceSnapshot(
            id: fields[2],
            title: fields[3],
            workingDirectory: fields[4],
            workspaceId: fields[0],
            workspaceName: fields[1]
        )
        return ShellraiserWorkspaceCreation(workspace: workspace, surface: surface)
    }

    /// Splits one existing surface and returns the new sibling surface snapshot,
    /// including the workspace context inherited from the source terminal.
    public func splitSurface(
        id: String,
        direction: ShellraiserSplitDirection,
        workingDirectory: String?
    ) throws -> ShellraiserSurfaceSnapshot {
        let directionLiteral = direction.appleScriptDirectionLiteral
        let output = try runScript(
            script: """
            on run argv
                set surfaceID to item 1 of argv
                set cwdText to item 2 of argv
                set us to ASCII character 31

                tell application applicationName
                    set targetTerminal to first terminal whose id is surfaceID
                    set config to new surface configuration
                    if cwdText is not "" then
                        set initial working directory of config to cwdText
                    end if
                    set createdTerminal to split terminal targetTerminal direction __SPLIT_DIRECTION__ with configuration config

                    set wsID to ""
                    set wsName to ""
                    set foundWS to false
                    repeat with ws in workspaces
                        repeat with tabItem in tabs of ws
                            repeat with t in terminals of tabItem
                                if (id of t) is (id of targetTerminal) then
                                    set wsID to id of ws
                                    set wsName to name of ws
                                    set foundWS to true
                                    exit repeat
                                end if
                            end repeat
                            if foundWS then exit repeat
                        end repeat
                        if foundWS then exit repeat
                    end repeat

                    return (id of createdTerminal) & us & (title of createdTerminal) & us & (working directory of createdTerminal) & us & wsID & us & wsName
                end tell
            end run
            """.replacingOccurrences(of: "__SPLIT_DIRECTION__", with: directionLiteral),
            arguments: [id, workingDirectory ?? ""]
        )

        let fields = parseFields(output, expectedCount: 5)
        return ShellraiserSurfaceSnapshot(
            id: fields[0],
            title: fields[1],
            workingDirectory: fields[2],
            workspaceId: fields[3].isEmpty ? nil : fields[3],
            workspaceName: fields[4].isEmpty ? nil : fields[4]
        )
    }

    /// Focuses one existing surface.
    public func focusSurface(id: String) throws {
        _ = try runScript(
            script: """
            on run argv
                set surfaceID to item 1 of argv

                tell application applicationName
                    set targetTerminal to first terminal whose id is surfaceID
                    focus terminal targetTerminal
                end tell
            end run
            """,
            arguments: [id]
        )
    }

    /// Sends literal text into one existing surface.
    public func sendText(_ text: String, toSurfaceWithID id: String) throws {
        _ = try runScript(
            script: """
            on run argv
                set surfaceID to item 1 of argv
                set payloadText to item 2 of argv

                tell application applicationName
                    set targetTerminal to first terminal whose id is surfaceID
                    input text payloadText to targetTerminal
                end tell
            end run
            """,
            arguments: [id, text]
        )
    }

    /// Sends one named key into one existing surface.
    public func sendKey(named keyName: String, toSurfaceWithID id: String) throws {
        _ = try runScript(
            script: """
            on run argv
                set surfaceID to item 1 of argv
                set keyName to item 2 of argv

                tell application applicationName
                    set targetTerminal to first terminal whose id is surfaceID
                    send key keyName to targetTerminal
                end tell
            end run
            """,
            arguments: [id, keyName]
        )
    }

    /// Returns all currently known workspaces.
    public func listWorkspaces() throws -> [ShellraiserWorkspaceSnapshot] {
        let output = try runScript(
            script: """
            on run argv
                set us to ASCII character 31
                set rs to ASCII character 30
                set recordsText to ""

                tell application applicationName
                    repeat with ws in workspaces
                        set selectedSurfaceID to ""
                        try
                            set selectedSurfaceID to id of first terminal of selected tab of ws
                        end try

                        set nextRecord to (id of ws) & us & (name of ws) & us & selectedSurfaceID
                        if recordsText is "" then
                            set recordsText to nextRecord
                        else
                            set recordsText to recordsText & rs & nextRecord
                        end if
                    end repeat
                end tell

                return recordsText
            end run
            """,
            arguments: []
        )

        return parseRecords(output).map {
            let fields = parseFields($0, expectedCount: 3)
            return ShellraiserWorkspaceSnapshot(
                id: fields[0],
                name: fields[1],
                selectedSurfaceId: fields[2].isEmpty ? nil : fields[2]
            )
        }
    }

    /// Returns all currently known surfaces, optionally scoped to one workspace.
    public func listSurfaces(workspaceID: String?) throws -> [ShellraiserSurfaceSnapshot] {
        let output = try runScript(
            script: """
            on run argv
                set workspaceFilter to item 1 of argv
                set us to ASCII character 31
                set rs to ASCII character 30
                set recordsText to ""

                tell application applicationName
                    repeat with ws in workspaces
                        if workspaceFilter is "" or (id of ws) is workspaceFilter then
                            repeat with tabItem in tabs of ws
                                repeat with term in terminals of tabItem
                                    set nextRecord to (id of term) & us & (title of term) & us & (working directory of term) & us & (id of ws) & us & (name of ws)
                                    if recordsText is "" then
                                        set recordsText to nextRecord
                                    else
                                        set recordsText to recordsText & rs & nextRecord
                                    end if
                                end repeat
                            end repeat
                        end if
                    end repeat
                end tell

                return recordsText
            end run
            """,
            arguments: [workspaceID ?? ""]
        )

        return parseRecords(output).map {
            let fields = parseFields($0, expectedCount: 5)
            return ShellraiserSurfaceSnapshot(
                id: fields[0],
                title: fields[1],
                workingDirectory: fields[2],
                workspaceId: fields[3],
                workspaceName: fields[4]
            )
        }
    }

    /// Returns one surface snapshot when the target still exists.
    public func surface(withID id: String) throws -> ShellraiserSurfaceSnapshot? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return try listSurfaces(workspaceID: nil).first {
            $0.id.caseInsensitiveCompare(normalizedID) == .orderedSame
        }
    }

    /// Closes one existing surface.
    public func closeSurface(id: String) throws {
        _ = try runScript(
            script: """
            on run argv
                set surfaceID to item 1 of argv

                tell application applicationName
                    set targetTerminal to first terminal whose id is surfaceID
                    close targetTerminal
                end tell
            end run
            """,
            arguments: [id]
        )
    }

    /// Closes one existing workspace.
    public func closeWorkspace(id: String) throws {
        _ = try runScript(
            script: """
            on run argv
                set workspaceID to item 1 of argv

                tell application applicationName
                    set targetWorkspace to first workspace whose id is workspaceID
                    close targetWorkspace
                end tell
            end run
            """,
            arguments: [id]
        )
    }

    /// Executes AppleScript after injecting the configured target application name.
    private func runScript(script: String, arguments: [String]) throws -> String {
        let preparedScript = script.replacingOccurrences(
            of: "tell application applicationName",
            with: "tell application \(applicationName.appleScriptLiteral)"
        )
        return try runner.run(script: preparedScript, arguments: arguments)
    }

    /// Parses one separator-delimited record into fields.
    private func parseFields(_ rawRecord: String, expectedCount: Int) -> [String] {
        let fields = rawRecord.components(separatedBy: Self.fieldSeparator)
        guard fields.count == expectedCount else {
            return fields + Array(repeating: "", count: max(0, expectedCount - fields.count))
        }
        return fields
    }

    /// Parses a record list separated with the configured record delimiter.
    private func parseRecords(_ rawOutput: String) -> [String] {
        guard !rawOutput.isEmpty else { return [] }
        return rawOutput.components(separatedBy: Self.recordSeparator).filter { !$0.isEmpty }
    }
}

private extension String {
    /// Escapes one string for direct embedding in AppleScript source.
    var appleScriptLiteral: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension ShellraiserSplitDirection {
    /// Returns the AppleScript enumeration literal used by the Shellraiser scripting dictionary.
    var appleScriptDirectionLiteral: String {
        rawValue
    }
}
