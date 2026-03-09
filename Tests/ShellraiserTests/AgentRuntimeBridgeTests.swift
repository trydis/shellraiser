import XCTest
@testable import Shellraiser

/// Covers managed-agent wrapper generation for runtime integration.
@MainActor
final class AgentRuntimeBridgeTests: XCTestCase {
    /// Verifies the Claude wrapper only emits completion events for top-level turn completion.
    func testPrepareRuntimeSupportWritesClaudeWrapperWithoutSubagentStopHook() throws {
        let bridge = AgentRuntimeBridge.shared

        bridge.prepareRuntimeSupport()

        let wrapperURL = bridge.binDirectory.appendingPathComponent("claude")
        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)

        XCTAssertTrue(wrapperContents.contains("\"Stop\""))
        XCTAssertFalse(wrapperContents.contains("\"SubagentStop\""))
    }
}
