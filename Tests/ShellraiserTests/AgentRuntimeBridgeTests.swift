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

        return AgentRuntimeBridge(rootURL: directory)
    }

    /// Verifies environment assembly stays local and does not require synchronous executable lookup.
    func testEnvironmentInjectsManagedWrapperVariablesWithoutResolvedBinaryPaths() throws {
        let bridge = try makeBridge()
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!

        let environment = bridge.environment(
            for: surfaceId,
            shellPath: "/bin/zsh",
            baseEnvironment: [
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "TERM": "xterm-256color"
            ]
        )

        XCTAssertEqual(
            environment["PATH"],
            "\(bridge.binDirectory.path):/usr/local/bin:/usr/bin:/bin"
        )
        XCTAssertEqual(environment["TERM"], "xterm-256color")
        XCTAssertEqual(environment["SHELLRAISER_EVENT_LOG"], bridge.eventLogURL.path)
        XCTAssertEqual(environment["SHELLRAISER_SURFACE_ID"], surfaceId.uuidString)
        XCTAssertEqual(
            environment["SHELLRAISER_HELPER_PATH"],
            bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete").path
        )
        XCTAssertEqual(environment["ZDOTDIR"], bridge.zshShimDirectory.path)
        XCTAssertEqual(environment["SHELLRAISER_WRAPPER_BIN"], bridge.binDirectory.path)
        XCTAssertEqual(environment["SHELLRAISER_ORIGINAL_PATH"], "/usr/local/bin:/usr/bin:/bin")
        XCTAssertNil(environment["SHELLRAISER_REAL_CLAUDE"])
        XCTAssertNil(environment["SHELLRAISER_REAL_CODEX"])
    }

    /// Verifies the Claude wrapper emits start, stop, permission-request, and selected notification hooks.
    func testPrepareRuntimeSupportWritesClaudeWrapperWithMappedNotificationHooks() throws {
        let bridge = try makeBridge()
        let wrapperURL = bridge.binDirectory.appendingPathComponent("claude")

        bridge.prepareRuntimeSupport()

        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)

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
        let lockURL = bridge.runtimeDirectory.appendingPathComponent("agent-completions.log.lock")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("codex:session|claudeCode:session)"))
        XCTAssertTrue(helperContents.contains("claudeCode:hook-session|codex:hook-session)"))
        XCTAssertTrue(helperContents.contains("/usr/bin/lockf"))
        XCTAssertTrue(helperContents.contains("${SHELLRAISER_EVENT_LOG}.lock"))
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
        XCTAssertFalse(helperContents.contains("codex:completed)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }

    /// Verifies runtime wrappers emit session identity metadata for later resume.
    func testPrepareRuntimeSupportWritesWrappersWithSessionIdentityCapture() throws {
        let bridge = try makeBridge()
        let claudeWrapperURL = bridge.binDirectory.appendingPathComponent("claude")
        let codexWrapperURL = bridge.binDirectory.appendingPathComponent("codex")

        bridge.prepareRuntimeSupport()

        let claudeWrapperContents = try String(contentsOf: claudeWrapperURL, encoding: .utf8)
        let codexWrapperContents = try String(contentsOf: codexWrapperURL, encoding: .utf8)

        // Claude wrapper: hook-based session and lifecycle
        XCTAssertTrue(claudeWrapperContents.contains("hook-session"))
        XCTAssertTrue(claudeWrapperContents.contains("lookup_path=\"${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}\""))
        XCTAssertTrue(claudeWrapperContents.contains("PATH=\"$lookup_path\" /usr/bin/which claude"))
        XCTAssertFalse(claudeWrapperContents.contains("SHELLRAISER_PREFERRED_CLAUDE_SESSION_ID"))
        XCTAssertFalse(claudeWrapperContents.contains("--session-id"))
        XCTAssertTrue(claudeWrapperContents.contains("claudeCode \"$surface\" exited"))

        // Codex wrapper: native hooks replace polling heuristics
        XCTAssertTrue(codexWrapperContents.contains("--dangerously-bypass-hook-trust"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.SessionStart"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.UserPromptSubmit"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.PreToolUse"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.PermissionRequest"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.Stop"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface hook-session"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface started"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface completed"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface exited"))
        XCTAssertTrue(codexWrapperContents.contains("lookup_path=\"${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}\""))
        XCTAssertTrue(codexWrapperContents.contains("PATH=\"$lookup_path\" /usr/bin/which codex"))
        XCTAssertTrue(codexWrapperContents.contains("--dangerously-bypass-hook-trust"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.SessionStart"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface hook-session"))
        XCTAssertTrue(codexWrapperContents.contains("codex $surface exited"))
        XCTAssertFalse(codexWrapperContents.contains("monitor_codex_session"))
        XCTAssertFalse(codexWrapperContents.contains("extract_codex_session_timestamp"))
        XCTAssertFalse(codexWrapperContents.contains("normalize_codex_session_timestamp"))
        XCTAssertFalse(codexWrapperContents.contains("monitor_pid"))
        XCTAssertFalse(codexWrapperContents.contains("notify_config"))
    }

    /// Verifies the zsh shim sources Ghostty shell integration when the runtime is active.
    ///
    /// The `.zshrc` shim must source `ghostty-integration` from `$GHOSTTY_RESOURCES_DIR`
    /// so that Ghostty's shell-integration features (title, CWD, marks) work inside
    /// Shellraiser-managed surfaces.
    func testPrepareRuntimeSupportWritesZshRcShimWithGhosttyIntegrationSourcing() throws {
        let bridge = try makeBridge()
        let zshRcURL = bridge.zshShimDirectory.appendingPathComponent(".zshrc")

        bridge.prepareRuntimeSupport()

        let zshRcContents = try String(contentsOf: zshRcURL, encoding: .utf8)

        XCTAssertTrue(zshRcContents.contains("GHOSTTY_RESOURCES_DIR"))
        XCTAssertTrue(zshRcContents.contains("ghostty-integration"))
        XCTAssertTrue(zshRcContents.contains("shell-integration/zsh/ghostty-integration"))
    }

    /// Verifies the helper can extract session identifiers from hook payloads for both runtimes.
    func testPrepareRuntimeSupportWritesHelperWithHookSessionParsing() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        // Both runtimes share the same sed-based JSON extraction via a unified case branch.
        XCTAssertTrue(helperContents.contains("claudeCode:hook-session|codex:hook-session)"))
        XCTAssertTrue(helperContents.contains("\"session_id\""))
        XCTAssertTrue(helperContents.contains("\"transcript_path\""))
        XCTAssertFalse(helperContents.contains("/usr/bin/python3"))
        XCTAssertTrue(helperContents.contains("phase=\"session\""))
    }
}
