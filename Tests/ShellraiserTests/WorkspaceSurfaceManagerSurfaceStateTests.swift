import XCTest
@testable import Shellraiser

/// Covers idle, completion, and title state mutations for surfaces.
final class WorkspaceSurfaceManagerSurfaceStateTests: WorkspaceTestCase {
    /// Verifies transitioning into idle marks the surface unread and refreshes activity time.
    func testSetIdleStateMarksUnreadWhenTransitioningToIdle() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let originalActivity = Date(timeIntervalSince1970: 1_700_000_000)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
            title: "Idle Candidate",
            lastActivity: originalActivity
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.setIdleState(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            isIdle: true,
            workspaces: &workspaces,
            persistence: persistence
        )

        let mutatedSurface = workspaces[0].rootPane.paneNode(id: paneId).flatMap { node -> SurfaceModel? in
            guard case .leaf(let leaf) = node else { return nil }
            return leaf.surfaces.first
        }
        XCTAssertEqual(mutatedSurface?.id, surface.id)
        XCTAssertTrue(mutatedSurface?.isIdle ?? false)
        XCTAssertTrue(mutatedSurface?.hasUnreadIdleNotification ?? false)
        XCTAssertEqual(mutatedSurface?.hasPendingCompletion, false)
        XCTAssertNotEqual(mutatedSurface?.lastActivity, originalActivity)
    }

    /// Verifies a fresh completion event records FIFO metadata and idle/unread state.
    func testMarkPendingCompletionAssignsCompletionMetadata() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000911")!,
            title: "Pending",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000913")!
        let completionTimestamp = Date(timeIntervalSince1970: 1_700_001_000)
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        let didEnqueue = manager.markPendingCompletion(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            agentType: .codex,
            sequence: 7,
            timestamp: completionTimestamp,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertTrue(didEnqueue)
        let snapshot = workspaces[0].rootPane.pendingSurfaceSnapshots().first
        XCTAssertEqual(snapshot?.paneId, paneId)
        XCTAssertEqual(snapshot?.surface.id, surface.id)
        XCTAssertEqual(snapshot?.surface.agentType, .codex)
        XCTAssertTrue(snapshot?.surface.isIdle ?? false)
        XCTAssertTrue(snapshot?.surface.hasUnreadIdleNotification ?? false)
        XCTAssertTrue(snapshot?.surface.hasPendingCompletion ?? false)
        XCTAssertEqual(snapshot?.surface.pendingCompletionSequence, 7)
        XCTAssertEqual(snapshot?.surface.lastCompletionAt, completionTimestamp)
    }

    /// Verifies clearing a handled completion resets all queue and unread state.
    func testClearPendingCompletionResetsCompletionFlags() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000921")!,
            title: "Handled",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 3,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_001_500)
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000922")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000923")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        let didClear = manager.clearPendingCompletion(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertTrue(didClear)
        let clearedSurface = workspaces[0].rootPane.paneNode(id: paneId).flatMap { node -> SurfaceModel? in
            guard case .leaf(let leaf) = node else { return nil }
            return leaf.surfaces.first
        }
        XCTAssertFalse(clearedSurface?.isIdle ?? true)
        XCTAssertFalse(clearedSurface?.hasUnreadIdleNotification ?? true)
        XCTAssertFalse(clearedSurface?.hasPendingCompletion ?? true)
        XCTAssertNil(clearedSurface?.pendingCompletionSequence)
    }

    /// Verifies empty or whitespace titles are normalized to the default tab title.
    func testSetSurfaceTitleTrimsWhitespaceAndFallsBackToTilde() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000931")!,
            title: "Old"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000932")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000933")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.setSurfaceTitle(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            title: "   \n",
            workspaces: &workspaces,
            persistence: persistence
        )

        let resolvedSurface = workspaces[0].rootPane.paneNode(id: paneId).flatMap { node -> SurfaceModel? in
            guard case .leaf(let leaf) = node else { return nil }
            return leaf.surfaces.first
        }
        XCTAssertEqual(resolvedSurface?.title, "~")
        XCTAssertEqual(persistence.load(), workspaces)
    }
}
