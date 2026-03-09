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

    /// Verifies re-enqueuing an already pending surface refreshes metadata without advancing queue identity.
    func testMarkPendingCompletionDoesNotReenqueueAlreadyPendingSurface() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let originalTimestamp = Date(timeIntervalSince1970: 1_700_001_600)
        let refreshTimestamp = Date(timeIntervalSince1970: 1_700_001_700)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000941")!,
            title: "Already Pending",
            agentType: .claudeCode,
            isIdle: true,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: true,
            pendingCompletionSequence: 9,
            lastCompletionAt: originalTimestamp
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000942")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000943")!
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
            sequence: 99,
            timestamp: refreshTimestamp,
            workspaces: &workspaces,
            persistence: persistence
        )

        let updatedSurface = self.surface(in: workspaces[0].rootPane, surfaceId: surface.id)
        XCTAssertFalse(didEnqueue)
        XCTAssertEqual(updatedSurface?.agentType, .codex)
        XCTAssertTrue(updatedSurface?.hasPendingCompletion ?? false)
        XCTAssertEqual(updatedSurface?.pendingCompletionSequence, 9)
        XCTAssertTrue(updatedSurface?.hasUnreadIdleNotification ?? false)
        XCTAssertEqual(updatedSurface?.lastCompletionAt, refreshTimestamp)
    }

    /// Verifies unchanged agent-type and title updates do not write persistence side effects.
    func testNoOpSetAgentTypeAndTitleDoNotPersist() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000951")!,
            title: "Stable",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000952")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000953")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.setAgentType(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            agentType: .codex,
            workspaces: &workspaces,
            persistence: persistence
        )
        manager.setSurfaceTitle(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            title: "Stable",
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertNil(persistence.load())
    }

    /// Verifies working-directory updates persist when the reported pwd changes.
    func testSetSurfaceWorkingDirectoryPersistsChangedPath() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000971")!,
            title: "Repo",
            lastActivity: Date(timeIntervalSince1970: 1_700_001_900)
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000972")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000973")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workingDirectory: "/tmp/project",
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertEqual(self.surface(in: workspaces[0].rootPane, surfaceId: surface.id)?.terminalConfig.workingDirectory, "/tmp/project")
        XCTAssertEqual(persistence.load(), workspaces)
    }

    /// Verifies unchanged working-directory reports do not persist redundant state.
    func testSetSurfaceWorkingDirectoryNoOpDoesNotPersist() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000981")!,
            title: "Stable"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000982")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000983")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workingDirectory: "/tmp",
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertNil(persistence.load())
    }

    /// Verifies clearing unread state and unchanged idle updates behave as expected.
    func testClearUnreadNotificationPersistsAndUnchangedIdleStateStaysInMemoryOnly() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let originalActivity = Date(timeIntervalSince1970: 1_700_001_800)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000961")!,
            title: "Unread",
            isIdle: false,
            hasUnreadIdleNotification: true,
            lastActivity: originalActivity
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000962")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000963")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.clearUnreadNotification(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workspaces: &workspaces,
            persistence: persistence
        )
        XCTAssertFalse(self.surface(in: workspaces[0].rootPane, surfaceId: surface.id)?.hasUnreadIdleNotification ?? true)
        XCTAssertEqual(persistence.load(), workspaces)

        try? FileManager.default.removeItem(
            at: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(ProcessInfo.processInfo.environment[WorkspacePersistence.appSupportSubdirectoryEnvironmentKey]!, isDirectory: true)
        )

        manager.setIdleState(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            isIdle: false,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertNotEqual(self.surface(in: workspaces[0].rootPane, surfaceId: surface.id)?.lastActivity, originalActivity)
        XCTAssertNil(persistence.load())
    }
}
