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

        XCTAssertTrue(helperContents.contains("codex:completed)"))
        XCTAssertTrue(helperContents.contains("codex:session|claudeCode:session)"))
        XCTAssertTrue(helperContents.contains("/usr/bin/lockf"))
        XCTAssertTrue(helperContents.contains("${SHELLRAISER_EVENT_LOG}.lock"))
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
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
}
