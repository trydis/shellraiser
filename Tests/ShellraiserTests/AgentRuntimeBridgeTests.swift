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

        XCTAssertTrue(wrapperContents.contains("\"UserPromptSubmit\""))
        XCTAssertTrue(wrapperContents.contains("\"PreToolUse\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"*\""))
        XCTAssertTrue(wrapperContents.contains("\"Stop\""))
        XCTAssertTrue(wrapperContents.contains("\"PermissionRequest\""))
        XCTAssertTrue(wrapperContents.contains("\"Notification\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"permission_prompt\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"elicitation_dialog\""))
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
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
    }
}
