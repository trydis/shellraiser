import XCTest
@testable import Shellraiser

/// Covers Agent HQ entry construction and cross-workspace sort order.
@MainActor
final class WorkspaceManagerAgentHQTests: WorkspaceTestCase {
    /// Verifies entries carry over surface, git, progress, and summary state from manager caches.
    func testAgentHQEntriesCarryOverPublishedManagerState() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!,
            title: "Fix flaky test",
            agentType: .codex,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000002002")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000002003")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Backend",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id)
            )
        ]
        manager.gitStatesBySurfaceId[surface.id] = ResolvedGitState(branchName: "feature/x", isLinkedWorktree: true)
        manager.progressBySurfaceId[surface.id] = SurfaceProgressReport(state: .set, progress: 42)
        manager.sessionSummariesBySurfaceId[surface.id] = "Running tests…"

        let entries = manager.agentHQEntries()

        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.workspaceId, workspaceId)
        XCTAssertEqual(entry.workspaceName, "Backend")
        XCTAssertEqual(entry.paneId, paneId)
        XCTAssertEqual(entry.surfaceId, surface.id)
        XCTAssertEqual(entry.title, "Fix flaky test")
        XCTAssertEqual(entry.agentType, .codex)
        XCTAssertEqual(entry.status, .idle)
        XCTAssertEqual(entry.branchName, "feature/x")
        XCTAssertTrue(entry.isLinkedWorktree)
        XCTAssertEqual(entry.progress?.progress, 42)
        XCTAssertEqual(entry.summary, "Running tests…")
        XCTAssertEqual(entry.lastActivity, surface.lastActivity)
    }

    /// Verifies global sort order: needsInput -> ready -> running -> idle, across workspaces.
    func testAgentHQEntriesSortByStatusPriorityAcrossWorkspaces() {
        let manager = makeWorkspaceManager()

        let idleSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002101")!,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let runningSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002102")!,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let readySurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002103")!,
            hasPendingCompletion: true,
            pendingCompletionSequence: 5,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let needsInputSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002104")!,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_050)
        )

        manager.workspaces = [
            makeWorkspace(
                name: "Workspace A",
                rootPane: makeLeaf(surfaces: [idleSurface, needsInputSurface])
            ),
            makeWorkspace(
                name: "Workspace B",
                rootPane: makeLeaf(surfaces: [runningSurface, readySurface])
            )
        ]
        manager.markSurfaceBusy(runningSurface.id)
        manager.markSurfaceAwaitingInput(needsInputSurface.id)

        let entries = manager.agentHQEntries()

        XCTAssertEqual(entries.map(\.surfaceId), [
            needsInputSurface.id,
            readySurface.id,
            runningSurface.id,
            idleSurface.id
        ])
    }

    /// Verifies ready rows break ties using the same FIFO sequence as the completion jump queue.
    func testAgentHQEntriesBreakReadyTiesByPendingCompletionSequence() {
        let manager = makeWorkspaceManager()

        let firstQueued = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002201")!,
            hasPendingCompletion: true,
            pendingCompletionSequence: 3,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_999)
        )
        let secondQueued = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002202")!,
            hasPendingCompletion: true,
            pendingCompletionSequence: 7,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_001)
        )

        manager.workspaces = [
            makeWorkspace(
                name: "Workspace",
                rootPane: makeLeaf(surfaces: [secondQueued, firstQueued])
            )
        ]

        let entries = manager.agentHQEntries()

        XCTAssertEqual(entries.map(\.surfaceId), [firstQueued.id, secondQueued.id])
    }

    /// Verifies same-status entries fall back to most-recent-activity-first ordering.
    func testAgentHQEntriesBreakIdleTiesByRecency() {
        let manager = makeWorkspaceManager()

        let older = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002301")!,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let newer = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002302")!,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_999)
        )

        manager.workspaces = [
            makeWorkspace(
                name: "Workspace",
                rootPane: makeLeaf(surfaces: [older, newer])
            )
        ]

        let entries = manager.agentHQEntries()

        XCTAssertEqual(entries.map(\.surfaceId), [newer.id, older.id])
    }
}
