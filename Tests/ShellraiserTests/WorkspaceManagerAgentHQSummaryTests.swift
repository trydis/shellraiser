import XCTest
@testable import Shellraiser

/// Covers Agent HQ summary refresh/clear wiring: overlay open, activity events, and surface teardown.
@MainActor
final class WorkspaceManagerAgentHQSummaryTests: WorkspaceTestCase {
    private var tempDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentHQSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        super.tearDown()
    }

    /// Verifies a direct, non-debounced refresh resolves a Claude transcript summary into the cache.
    func testRefreshSessionSummaryPopulatesCacheFromClaudeTranscript() async {
        let transcriptURL = tempDirectoryURL.appendingPathComponent("transcript.jsonl")
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Refactoring the parser."}]}}"#
        try? line.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let manager = makeWorkspaceManager(sessionSummaryService: service)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003001")!,
            agentType: .claudeCode,
            transcriptPath: transcriptURL.path
        )
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003002")!
        manager.workspaces = [
            makeWorkspace(id: workspaceId, name: "Workspace", rootPane: makeLeaf(surfaces: [surface]))
        ]

        await manager.refreshSessionSummary(workspaceId: workspaceId, surfaceId: surface.id, debounced: false).value

        XCTAssertEqual(manager.sessionSummariesBySurfaceId[surface.id], "Refactoring the parser.")
    }

    /// Verifies toggling Agent HQ open triggers a refresh for every live surface.
    func testTogglingAgentHQOnRefreshesAllSurfaceSummaries() async {
        let transcriptURL = tempDirectoryURL.appendingPathComponent("transcript.jsonl")
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Reviewing the diff."}]}}"#
        try? line.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let service = SessionSummaryService(
            codexSessionsRootURL: tempDirectoryURL.appendingPathComponent("codex"),
            copilotHomeURL: tempDirectoryURL.appendingPathComponent("copilot")
        )
        let manager = makeWorkspaceManager(sessionSummaryService: service)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003101")!,
            agentType: .claudeCode,
            transcriptPath: transcriptURL.path
        )
        manager.workspaces = [
            makeWorkspace(name: "Workspace", rootPane: makeLeaf(surfaces: [surface]))
        ]

        manager.toggleAgentHQ()
        XCTAssertTrue(manager.isAgentHQPresented)

        // The refresh task is fire-and-forget from toggleAgentHQ; await the tracked task directly.
        await manager.sessionSummaryTasks[surface.id]?.value

        XCTAssertEqual(manager.sessionSummariesBySurfaceId[surface.id], "Reviewing the diff.")
    }

    /// Verifies closing a surface clears its cached summary from published manager state.
    func testClearSessionSummaryRemovesCachedEntry() {
        let manager = makeWorkspaceManager()
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003201")!
        manager.sessionSummariesBySurfaceId[surfaceId] = "Stale summary"

        manager.clearSessionSummary(surfaceId: surfaceId)

        XCTAssertNil(manager.sessionSummariesBySurfaceId[surfaceId])
    }
}
