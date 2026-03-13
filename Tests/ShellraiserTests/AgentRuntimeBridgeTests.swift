import XCTest
@testable import Shellraiser

/// Covers managed-agent wrapper generation for runtime integration.
@MainActor
final class AgentRuntimeBridgeTests: XCTestCase {
    /// Verifies the Claude wrapper emits start, stop, permission-request, and selected notification hooks.
    func testPrepareRuntimeSupportWritesClaudeWrapperWithMappedNotificationHooks() throws {
        let bridge = AgentRuntimeBridge.shared
        let wrapperURL = bridge.binDirectory.appendingPathComponent("claude")

        try? FileManager.default.removeItem(at: wrapperURL)

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
        let bridge = AgentRuntimeBridge.shared
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        try? FileManager.default.removeItem(at: helperURL)

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("codex:completed)"))
        XCTAssertTrue(helperContents.contains("codex:session|claudeCode:session)"))
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
    }

    /// Verifies runtime wrappers emit session identity metadata for later resume.
    func testPrepareRuntimeSupportWritesWrappersWithSessionIdentityCapture() throws {
        let bridge = AgentRuntimeBridge.shared
        let claudeWrapperURL = bridge.binDirectory.appendingPathComponent("claude")
        let codexWrapperURL = bridge.binDirectory.appendingPathComponent("codex")

        try? FileManager.default.removeItem(at: claudeWrapperURL)
        try? FileManager.default.removeItem(at: codexWrapperURL)

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
        XCTAssertTrue(codexWrapperContents.contains("extract_codex_session_timestamp"))
        XCTAssertTrue(codexWrapperContents.contains("normalize_codex_session_timestamp"))
        XCTAssertTrue(codexWrapperContents.contains("timestamp_is_at_or_after"))
        XCTAssertTrue(codexWrapperContents.contains("sed -E 's/\\.[0-9]+Z$/Z/'"))
    }

    /// Verifies the helper can extract Claude hook session identifiers from stdin payloads.
    func testPrepareRuntimeSupportWritesHelperWithClaudeHookSessionParsing() throws {
        let bridge = AgentRuntimeBridge.shared
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        try? FileManager.default.removeItem(at: helperURL)

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("claudeCode:hook-session"))
        XCTAssertTrue(helperContents.contains("\"session_id\""))
        XCTAssertTrue(helperContents.contains("\"transcript_path\""))
        XCTAssertFalse(helperContents.contains("/usr/bin/python3"))
        XCTAssertTrue(helperContents.contains("phase=\"session\""))
    }
}
