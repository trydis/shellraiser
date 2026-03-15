import XCTest
@testable import Shellraiser

/// Covers managed-agent wrapper generation for runtime integration.
@MainActor
final class AgentRuntimeBridgeTests: XCTestCase {
    /// Creates a bridge rooted in a unique temporary directory for test isolation.
    private func makeBridge(testName: String = #function) throws -> AgentRuntimeBridge {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-\(sanitizedTestName)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        return AgentRuntimeBridge(rootURL: directory, allowsTmuxShimDiscovery: false)
    }

    /// Verifies the Claude wrapper emits start, stop, permission-request, and selected notification hooks.
    func testPrepareRuntimeSupportWritesClaudeWrapperWithMappedNotificationHooks() throws {
        let bridge = try makeBridge()
        let wrapperURL = bridge.binDirectory.appendingPathComponent("claude")

        bridge.prepareRuntimeSupport()

        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)

        XCTAssertTrue(wrapperContents.contains("\"teammateMode\": \"tmux\""))
        XCTAssertTrue(wrapperContents.contains("teammate_mode_args=\"--teammate-mode tmux\""))
        XCTAssertTrue(wrapperContents.contains("claude-wrapper"))
        XCTAssertTrue(wrapperContents.contains("SHELLRAISER_WRAPPER_DEBUG_LOG"))
        XCTAssertTrue(wrapperContents.contains("SHELLRAISER_CLAUDE_DEBUG_LOG"))
        XCTAssertTrue(wrapperContents.contains("--debug-file \"$SHELLRAISER_CLAUDE_DEBUG_LOG\""))
        XCTAssertTrue(wrapperContents.contains("\"$real\" --settings \"$settings_file\" --teammate-mode tmux --debug-file \"$SHELLRAISER_CLAUDE_DEBUG_LOG\" \"$@\""))
        XCTAssertTrue(wrapperContents.contains("\"$real\" --settings \"$settings_file\" --debug-file \"$SHELLRAISER_CLAUDE_DEBUG_LOG\" \"$@\""))
        XCTAssertTrue(wrapperContents.contains("\"SessionStart\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"startup\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"resume\""))
        XCTAssertTrue(wrapperContents.contains("\"UserPromptSubmit\""))
        XCTAssertTrue(wrapperContents.contains("\"PreToolUse\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"*\""))
        XCTAssertTrue(wrapperContents.contains("\"Stop\""))
        XCTAssertTrue(wrapperContents.contains("\"PermissionRequest\""))
        XCTAssertTrue(wrapperContents.contains("\"Notification\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"permission_prompt\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"elicitation_dialog\""))
        XCTAssertTrue(wrapperContents.contains("claudeCode \"$surface\" exited"))
        XCTAssertFalse(wrapperContents.contains("\"SubagentStop\""))
    }

    /// Verifies the helper script only matches fully qualified Codex runtime phases.
    func testPrepareRuntimeSupportWritesHelperWithoutBareCodexCase() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("codex:completed)"))
        XCTAssertTrue(helperContents.contains("codex:session|claudeCode:session)"))
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
    }

    /// Verifies runtime wrappers emit session identity metadata for later resume.
    func testPrepareRuntimeSupportWritesWrappersWithSessionIdentityCapture() throws {
        let bridge = try makeBridge()
        let claudeWrapperURL = bridge.binDirectory.appendingPathComponent("claude")
        let codexWrapperURL = bridge.binDirectory.appendingPathComponent("codex")

        bridge.prepareRuntimeSupport()

        let claudeWrapperContents = try String(contentsOf: claudeWrapperURL, encoding: .utf8)
        let codexWrapperContents = try String(contentsOf: codexWrapperURL, encoding: .utf8)

        XCTAssertTrue(claudeWrapperContents.contains("hook-session"))
        XCTAssertFalse(claudeWrapperContents.contains("SHELLRAISER_PREFERRED_CLAUDE_SESSION_ID"))
        XCTAssertFalse(claudeWrapperContents.contains("--session-id"))
        XCTAssertTrue(claudeWrapperContents.contains("claudeCode \"$surface\" exited"))
        XCTAssertTrue(codexWrapperContents.contains("monitor_codex_session"))
        XCTAssertTrue(codexWrapperContents.contains("codex \"$surface\" session"))
        XCTAssertTrue(codexWrapperContents.contains("codex \"$surface\" exited"))
        XCTAssertFalse(codexWrapperContents.contains("codex \"$surface\" started"))
        XCTAssertTrue(codexWrapperContents.contains("extract_codex_session_timestamp"))
        XCTAssertFalse(codexWrapperContents.contains("extract_codex_surface_id"))
        XCTAssertFalse(codexWrapperContents.contains("surface_matches_current_codex_session"))
        XCTAssertTrue(codexWrapperContents.contains("normalize_codex_session_timestamp"))
        XCTAssertTrue(codexWrapperContents.contains("timestamp_is_at_or_after"))
        XCTAssertTrue(codexWrapperContents.contains("while :; do"))
        XCTAssertFalse(codexWrapperContents.contains("while [ \"$attempts\" -lt 40 ]; do"))
        XCTAssertFalse(codexWrapperContents.contains("attempts=$((attempts + 1))"))
        XCTAssertTrue(codexWrapperContents.contains("printf '%-9.9s'"))
        XCTAssertTrue(codexWrapperContents.contains("monitor_pid=\"$!\""))
        XCTAssertTrue(codexWrapperContents.contains("rm -f \"$stamp_file\""))
        XCTAssertTrue(codexWrapperContents.contains("wait \"$monitor_pid\" 2>/dev/null || true"))
    }

    /// Verifies the helper can extract Claude hook session identifiers from stdin payloads.
    func testPrepareRuntimeSupportWritesHelperWithClaudeHookSessionParsing() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("claudeCode:hook-session"))
        XCTAssertTrue(helperContents.contains("\"session_id\""))
        XCTAssertTrue(helperContents.contains("\"transcript_path\""))
        XCTAssertFalse(helperContents.contains("/usr/bin/python3"))
        XCTAssertTrue(helperContents.contains("phase=\"session\""))
    }

    /// Verifies the runtime bridge installs a tmux wrapper only for Claude-managed subprocess PATH injection.
    func testPrepareRuntimeSupportWritesTmuxWrapperIntoTeamBinWhenShimIsAvailable() throws {
        let shimURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-tmux-\(UUID().uuidString)")
        let shimContents = "#!/bin/sh\nexit 0\n"
        FileManager.default.createFile(atPath: shimURL.path, contents: Data(shimContents.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: shimURL)
        }

        let sanitizedTestName = #function
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-\(sanitizedTestName)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let bridge = AgentRuntimeBridge(
            rootURL: directory,
            tmuxShimExecutableURLOverride: shimURL,
            allowsTmuxShimDiscovery: false
        )
        let wrapperURL = bridge.teamBinDirectory.appendingPathComponent("tmux")
        let claudeWrapperURL = bridge.binDirectory.appendingPathComponent("claude")

        bridge.prepareRuntimeSupport()

        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)
        let claudeWrapperContents = try String(contentsOf: claudeWrapperURL, encoding: .utf8)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wrapperURL.path))
        XCTAssertTrue(wrapperContents.contains(shimURL.path))
        XCTAssertTrue(wrapperContents.contains("tmux-wrapper"))
        XCTAssertTrue(wrapperContents.contains("SHELLRAISER_REAL_TMUX_SHIM"))
        XCTAssertTrue(claudeWrapperContents.contains("SHELLRAISER_TEAM_BIN"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.binDirectory.appendingPathComponent("tmux").path))
    }

    /// Verifies the terminal environment exposes the tmux shim only inside Shellraiser-managed terminals.
    func testEnvironmentPrependsTeamBinWhenTmuxShimIsAvailable() throws {
        let shimURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-tmux-env-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: shimURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: shimURL)
        }

        let bridge = AgentRuntimeBridge(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShellraiserTests-env-\(UUID().uuidString)", isDirectory: true),
            tmuxShimExecutableURLOverride: shimURL,
            allowsTmuxShimDiscovery: false
        )
        let environment = bridge.environment(
            for: UUID(),
            shellPath: "/bin/zsh",
            baseEnvironment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(environment["SHELLRAISER_TEAM_BIN"], bridge.teamBinDirectory.path)
        XCTAssertEqual(environment["SHELLRAISER_WRAPPER_DEBUG_LOG"], bridge.debugLogURL.path)
        XCTAssertEqual(
            environment["SHELLRAISER_CLAUDE_DEBUG_LOG"],
            bridge.runtimeDirectory.appendingPathComponent("claude-debug-\(environment["SHELLRAISER_SURFACE_ID"]!).log").path
        )
        XCTAssertEqual(
            environment["PATH"],
            "\(bridge.binDirectory.path):\(bridge.teamBinDirectory.path):/usr/bin:/bin"
        )
    }

    /// Verifies zsh bootstrap files preserve the tmux shim path and exported team-bin metadata.
    func testPrepareRuntimeSupportWritesZshShimsWithTeamBinPathPreserved() throws {
        let shimURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-tmux-zsh-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: shimURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: shimURL)
        }

        let bridge = AgentRuntimeBridge(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShellraiserTests-zsh-\(UUID().uuidString)", isDirectory: true),
            tmuxShimExecutableURLOverride: shimURL,
            allowsTmuxShimDiscovery: false
        )
        let zshRcURL = bridge.zshShimDirectory.appendingPathComponent(".zshrc")

        bridge.prepareRuntimeSupport()

        let zshRcContents = try String(contentsOf: zshRcURL, encoding: .utf8)
        XCTAssertTrue(zshRcContents.contains("SHELLRAISER_TEAM_BIN:+${SHELLRAISER_TEAM_BIN}:"))
        XCTAssertTrue(zshRcContents.contains("export SHELLRAISER_EVENT_LOG"))
        XCTAssertTrue(zshRcContents.contains("SHELLRAISER_WRAPPER_DEBUG_LOG"))
        XCTAssertTrue(zshRcContents.contains("SHELLRAISER_CLAUDE_DEBUG_LOG"))
        XCTAssertTrue(zshRcContents.contains("SHELLRAISER_TEAM_BIN"))
    }
}
