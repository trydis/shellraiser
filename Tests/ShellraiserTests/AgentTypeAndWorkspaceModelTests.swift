import XCTest
@testable import Shellraiser

/// Covers small value-type behaviors that are easy to regress.
final class AgentTypeAndWorkspaceModelTests: XCTestCase {
    /// Verifies session resume commands are emitted only for non-empty session identifiers.
    func testResumeCommandUsesExpectedExecutableArguments() {
        XCTAssertNil(AgentType.codex.resumeCommand(sessionId: "   "))

        let claudeResumeCommand = AgentType.claudeCode.resumeCommand(sessionId: "abc123")
        let codexResumeCommand = AgentType.codex.resumeCommand(sessionId: "xyz789")

        XCTAssertEqual(claudeResumeCommand?.command, "claude")
        XCTAssertEqual(claudeResumeCommand?.arguments, ["--resume", "abc123"])
        XCTAssertEqual(codexResumeCommand?.command, "codex")
        XCTAssertEqual(codexResumeCommand?.arguments, ["resume", "xyz789"])
    }

    /// Verifies a new workspace starts focused on its initial surface.
    func testMakeDefaultWorkspaceFocusesInitialSurface() {
        let initialSurface = SurfaceModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            title: "Initial",
            agentType: .codex,
            sessionId: "initial-session",
            shouldResumeSession: true,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp",
                shell: "/bin/zsh",
                environment: ["TERM": "xterm-256color"]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let workspace = WorkspaceModel.makeDefault(name: "Tests", initialSurface: initialSurface)

        XCTAssertEqual(workspace.name, "Tests")
        XCTAssertEqual(workspace.focusedSurfaceId, initialSurface.id)
        XCTAssertEqual(workspace.rootPane.firstActiveSurfaceId(), initialSurface.id)
        XCTAssertNil(workspace.zoomedPaneId)
    }
}
