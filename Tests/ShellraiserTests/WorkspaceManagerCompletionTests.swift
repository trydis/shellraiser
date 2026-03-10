import XCTest
@testable import Shellraiser

/// Covers completion queue ordering and manager-level orchestration.
@MainActor
final class WorkspaceManagerCompletionTests: WorkspaceTestCase {
    /// Verifies persisted completion metadata seeds the cursor once and subsequent loads are ignored.
    func testLoadWorkspacesSynchronizesCursorAndOnlyLoadsOnce() {
        let persistence = makePersistence()
        let runtimeBridge = MockAgentRuntimeBridge()
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let pendingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001101")!,
            title: "Pending",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 9,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_000)
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001102")!
        let persistedWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001103")!,
            name: "Persisted",
            rootPane: makeLeaf(paneId: paneId, surfaces: [pendingSurface], activeSurfaceId: pendingSurface.id),
            focusedSurfaceId: pendingSurface.id
        )
        persistence.save([persistedWorkspace])

        let manager = makeWorkspaceManager(
            persistence: persistence,
            runtimeBridge: runtimeBridge,
            notifications: notifications,
            eventMonitor: eventMonitor
        )

        manager.loadWorkspaces()
        XCTAssertEqual(manager.workspaces, [persistedWorkspace])
        XCTAssertEqual(manager.nextPendingCompletionSequence, 10)
        XCTAssertEqual(runtimeBridge.prepareRuntimeSupportCallCount, 1)

        manager.workspaces = []
        manager.loadWorkspaces()
        XCTAssertEqual(manager.workspaces, [])
        XCTAssertEqual(manager.nextPendingCompletionSequence, 10)
    }

    /// Verifies pending targets are globally sorted by sequence rather than workspace order.
    func testPendingCompletionTargetsSortBySequenceAcrossWorkspaces() {
        let manager = makeWorkspaceManager()
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001111")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001112")!
        let laterSequenceSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001113")!,
            title: "Later",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 20,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_200)
        )
        let earlierSequenceSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001114")!,
            title: "Earlier",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 5,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_100)
        )
        manager.workspaces = [
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001115")!,
                name: "First",
                rootPane: makeLeaf(paneId: firstPaneId, surfaces: [laterSequenceSurface], activeSurfaceId: laterSequenceSurface.id),
                focusedSurfaceId: laterSequenceSurface.id
            ),
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001116")!,
                name: "Second",
                rootPane: makeLeaf(paneId: secondPaneId, surfaces: [earlierSequenceSurface], activeSurfaceId: earlierSequenceSurface.id),
                focusedSurfaceId: earlierSequenceSurface.id
            )
        ]

        let targets = manager.pendingCompletionTargets()

        XCTAssertEqual(targets.map(\.surface.id), [earlierSequenceSurface.id, laterSequenceSurface.id])
        XCTAssertEqual(targets.map(\.sequence), [5, 20])
    }

    /// Verifies pane queue metadata and highlight state reflect the global pending-completion ordering.
    func testQueuePositionAndHighlightStateReflectCurrentAndQueuedPanes() {
        let manager = makeWorkspaceManager()
        let currentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001121")!
        let queuedPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001122")!
        let currentSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001123")!,
            title: "Current",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 1,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_300)
        )
        let queuedSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001124")!,
            title: "Queued",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 2,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_400)
        )
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001125")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: .split(
                    PaneSplitModel(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001126")!,
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: makeLeaf(paneId: currentPaneId, surfaces: [currentSurface], activeSurfaceId: currentSurface.id),
                        second: makeLeaf(paneId: queuedPaneId, surfaces: [queuedSurface], activeSurfaceId: queuedSurface.id)
                    )
                ),
                focusedSurfaceId: currentSurface.id
            )
        ]

        let currentPosition = manager.pendingCompletionQueuePosition(workspaceId: workspaceId, paneId: currentPaneId)
        let queuedPosition = manager.pendingCompletionQueuePosition(workspaceId: workspaceId, paneId: queuedPaneId)

        XCTAssertEqual(currentPosition?.position, 1)
        XCTAssertEqual(currentPosition?.total, 2)
        XCTAssertEqual(queuedPosition?.position, 2)
        XCTAssertEqual(queuedPosition?.total, 2)
        if case .current = manager.completionHighlightState(workspaceId: workspaceId, paneId: currentPaneId) {
        } else {
            XCTFail("Expected current pane highlight state.")
        }

        if case .queued = manager.completionHighlightState(workspaceId: workspaceId, paneId: queuedPaneId) {
        } else {
            XCTFail("Expected queued pane highlight state.")
        }
    }

    /// Verifies completion events for mounted surfaces enqueue notifications and advance the cursor.
    func testHandleCompletionEventEnqueuesNotificationForKnownSurface() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001131")!,
            title: "Known Surface"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001132")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001133")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Known Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]
        manager.nextPendingCompletionSequence = 4

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_500),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .completed,
                payload: "payload"
            )
        )

        XCTAssertEqual(manager.nextPendingCompletionSequence, 5)
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)
        XCTAssertEqual(notifications.scheduledNotifications.first?.workspaceName, "Known Workspace")
        XCTAssertEqual(manager.pendingCompletionTargets().map(\.surface.id), [surface.id])
    }

    /// Verifies activity events drive workspace-level busy state until completion arrives.
    func testActivityEventsMarkWorkspaceBusyUntilCompletion() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001134")!,
            title: "Busy Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001135")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001136")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Busy Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_510),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .started,
                payload: ""
            )
        )

        XCTAssertTrue(manager.isWorkspaceWorking(workspaceId: workspaceId))

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_520),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .completed,
                payload: ""
            )
        )

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies Codex terminal input marks the owning workspace busy until completion is observed.
    func testNoteSurfaceActivityMarksCodexWorkspaceBusy() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001137")!,
            title: "Codex Surface",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001138")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001139")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Codex Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        manager.noteSurfaceActivity(workspaceId: workspaceId, surfaceId: surface.id)

        XCTAssertTrue(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies closing a busy surface clears the workspace working indicator state.
    func testCloseSurfaceClearsBusyWorkspaceState() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001140")!,
            title: "Closing Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001147")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001148")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Closing Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.markSurfaceBusy(surface.id)

        manager.closeSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies jumping to the next completed session selects and clears the head of the queue.
    func testJumpToNextCompletedSessionSelectsWorkspaceAndClearsCompletion() {
        let notifications = MockAgentCompletionNotificationManager()
        let manager = makeWorkspaceManager(notifications: notifications)
        let targetSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001141")!,
            title: "Target",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 1,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_600)
        )
        let otherSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001142")!,
            title: "Other",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 2,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_004_700)
        )
        let targetPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001143")!
        let otherPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001144")!
        let targetWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001145")!
        let otherWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001146")!
        manager.workspaces = [
            makeWorkspace(
                id: otherWorkspaceId,
                name: "Other",
                rootPane: makeLeaf(paneId: otherPaneId, surfaces: [otherSurface], activeSurfaceId: otherSurface.id),
                focusedSurfaceId: otherSurface.id
            ),
            makeWorkspace(
                id: targetWorkspaceId,
                name: "Target",
                rootPane: makeLeaf(paneId: targetPaneId, surfaces: [targetSurface], activeSurfaceId: targetSurface.id),
                focusedSurfaceId: nil
            )
        ]

        manager.jumpToNextCompletedSession()

        XCTAssertEqual(manager.window.selectedWorkspaceId, targetWorkspaceId)
        XCTAssertEqual(manager.workspaces[1].focusedSurfaceId, targetSurface.id)
        XCTAssertEqual(notifications.removedSurfaceIds, [targetSurface.id])
        XCTAssertFalse(surface(in: manager.workspaces[1].rootPane, paneId: targetPaneId)?.hasPendingCompletion ?? true)
        XCTAssertEqual(manager.pendingCompletionTargets().map(\.surface.id), [otherSurface.id])
    }

    /// Verifies handled completion highlights move from hold to fade and then expire.
    func testCompletionHighlightStateReturnsRecentHoldRecentFadeAndThenNone() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001151")!,
            title: "Handled"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001152")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001153")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        let now = Date()
        manager.recentlyHandledSurfaceFadeStarts[surface.id] = now.addingTimeInterval(5)
        manager.recentlyHandledSurfaceExpirations[surface.id] = now.addingTimeInterval(6.2)
        if case .recentHold = manager.completionHighlightState(workspaceId: workspaceId, paneId: paneId) {
        } else {
            XCTFail("Expected recent hold highlight state.")
        }

        manager.recentlyHandledSurfaceFadeStarts[surface.id] = now.addingTimeInterval(-1)
        manager.recentlyHandledSurfaceExpirations[surface.id] = now.addingTimeInterval(1)
        if case .recentFade = manager.completionHighlightState(workspaceId: workspaceId, paneId: paneId) {
        } else {
            XCTFail("Expected recent fade highlight state.")
        }

        manager.recentlyHandledSurfaceFadeStarts[surface.id] = now.addingTimeInterval(-10)
        manager.recentlyHandledSurfaceExpirations[surface.id] = now.addingTimeInterval(-1)
        if case .none = manager.completionHighlightState(workspaceId: workspaceId, paneId: paneId) {
        } else {
            XCTFail("Expected no highlight state after expiration.")
        }
        XCTAssertTrue(manager.recentlyHandledSurfaceFadeStarts.isEmpty)
        XCTAssertTrue(manager.recentlyHandledSurfaceExpirations.isEmpty)
    }

    /// Verifies queue-position lookup returns nil when the pane is not part of the pending queue.
    func testPendingCompletionQueuePositionReturnsNilForUnknownPaneOrEmptyQueue() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001161")!,
            title: "Only"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001162")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001163")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        XCTAssertNil(manager.pendingCompletionQueuePosition(workspaceId: workspaceId, paneId: paneId))

        _ = manager.surfaceManager.markPendingCompletion(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            agentType: .codex,
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_004_900),
            workspaces: &manager.workspaces,
            persistence: manager.persistence
        )

        XCTAssertNil(
            manager.pendingCompletionQueuePosition(
                workspaceId: workspaceId,
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001199")!
            )
        )
    }
}
