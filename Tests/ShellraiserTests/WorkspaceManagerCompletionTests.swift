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

    /// Verifies Codex started events mark a workspace busy through the native hook.
    func testCodexStartedEventMarksWorkspaceBusy() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001170")!,
            title: "Codex Launch Surface",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001171")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001172")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Codex Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_521),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .started,
                payload: ""
            )
        )

        XCTAssertTrue(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies session-identity events persist the resolved runtime and resume identifier.
    func testSessionEventPersistsSurfaceSessionIdentity() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(
            persistence: persistence,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001137")!,
            title: "Session Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001138")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001139")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_525),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .session,
                payload: "DA38C283-06C0-4D30-AADA-C9552606D76A\n/tmp/claude-transcript.jsonl"
            )
        )

        let persistedSurface = self.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)
        XCTAssertEqual(persistedSurface?.agentType, .claudeCode)
        XCTAssertEqual(persistedSurface?.sessionId, "da38c283-06c0-4d30-aada-c9552606d76a")
        XCTAssertEqual(persistedSurface?.transcriptPath, "/tmp/claude-transcript.jsonl")
        XCTAssertTrue(persistedSurface?.shouldResumeSession ?? false)
        XCTAssertEqual(persistence.load(), manager.workspaces)
    }

    /// Verifies exit events disable future auto-resume while the app remains running.
    func testExitedEventClearsResumeEligibilityWhenNotTerminating() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(
            persistence: persistence,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001149")!,
            title: "Exit Surface",
            sessionId: "existing-session",
            shouldResumeSession: true
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001150")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001151")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_530),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .exited,
                payload: ""
            )
        )

        let persistedSurface = self.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)
        XCTAssertFalse(persistedSurface?.shouldResumeSession ?? true)
        XCTAssertEqual(persistedSurface?.sessionId, "existing-session")
        XCTAssertEqual(persistence.load(), manager.workspaces)
    }

    /// Verifies app termination preserves resume eligibility for sessions that were still active.
    func testExitedEventDoesNotClearResumeEligibilityDuringTermination() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(
            persistence: persistence,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001152")!,
            title: "Terminating Surface",
            sessionId: "existing-session",
            shouldResumeSession: true
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001153")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001154")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.prepareForTermination()

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_531),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .exited,
                payload: ""
            )
        )

        let persistedSurface = self.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)
        XCTAssertTrue(persistedSurface?.shouldResumeSession ?? false)
        XCTAssertEqual(persistedSurface?.sessionId, "existing-session")
        XCTAssertEqual(persistence.load(), manager.workspaces)
    }

    /// Verifies live child exits still close their owning surface outside app termination.
    func testHandleSurfaceChildExitClosesSurfaceWhenNotTerminating() {
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(persistence: persistence)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001155")!,
            title: "Exited Surface",
            sessionId: "existing-session",
            shouldResumeSession: true
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001156")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001157")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        manager.handleSurfaceChildExit(workspaceId: workspaceId, surfaceId: surface.id)

        XCTAssertNil(self.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id))
        XCTAssertEqual(persistence.load(), manager.workspaces)
    }

    /// Verifies app shutdown ignores child exits so resumable surfaces remain persisted.
    func testHandleSurfaceChildExitPreservesSurfaceDuringTermination() {
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(persistence: persistence)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001158")!,
            title: "Terminating Exit Surface",
            sessionId: "existing-session",
            shouldResumeSession: true
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001159")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001160")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.prepareForTermination()

        manager.handleSurfaceChildExit(workspaceId: workspaceId, surfaceId: surface.id)

        let persistedSurface = self.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)
        XCTAssertEqual(persistedSurface?.sessionId, "existing-session")
        XCTAssertTrue(persistedSurface?.shouldResumeSession ?? false)
        XCTAssertEqual(persistence.load(), manager.workspaces)
    }

    /// Verifies submit-only Codex input does not mark busy before runtime session discovery.
    func testHandleSurfaceInputDoesNotMarkCodexBusyWithoutKnownSession() {
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

        manager.handleSurfaceInput(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            input: .userSubmit
        )

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies Codex submit input does not mark busy; the native hook owns that transition.
    func testHandleSurfaceInputDoesNotMarkCodexBusyAfterSessionEvent() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001161")!,
            title: "Codex Submit Surface",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001162")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001163")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Codex Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_540),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .session,
                payload: "session-123"
            )
        )

        manager.handleSurfaceInput(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            input: .userSubmit
        )

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies non-submit Codex input does not mark the workspace busy after session discovery.
    func testHandleSurfaceInputIgnoresNonSubmitCodexInput() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001164")!,
            title: "Codex Typing Surface",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001165")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001166")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Codex Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_541),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .session,
                payload: "session-456"
            )
        )

        manager.handleSurfaceInput(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            input: .userInput
        )

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
    }

    /// Verifies runtime exit clears the Codex submit gate after a session was known.
    func testExitedEventClearsKnownCodexSessionGate() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001167")!,
            title: "Codex Exit Surface",
            agentType: .codex
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001168")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001169")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Codex Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_542),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .session,
                payload: "session-789"
            )
        )
        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_004_543),
                agentType: .codex,
                surfaceId: surface.id,
                phase: .exited,
                payload: ""
            )
        )

        manager.handleSurfaceInput(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            input: .scriptedSubmit
        )

        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
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

    // MARK: - Waiting-for-input state

    /// Verifies waiting-for-input events populate awaitingInputSurfaceIds without enqueuing a completion.
    func testWaitingForInputEventMarksAwaitingWithoutEnqueuingCompletion() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001180")!,
            title: "Waiting Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001181")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001182")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Waiting Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_000),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .waitingForInput,
                payload: ""
            )
        )

        XCTAssertTrue(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertTrue(manager.isWorkspaceAwaitingInput(workspaceId: workspaceId))
        XCTAssertEqual(manager.awaitingInputCount(workspaceId: workspaceId), 1)
        XCTAssertTrue(manager.hasAwaitingInput)
        XCTAssertTrue(manager.pendingCompletionTargets().isEmpty, "Should not enqueue a completion")
        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)
        XCTAssertEqual(notifications.scheduledNotifications.first?.kind, .waitingForInput)
        XCTAssertEqual(notifications.scheduledNotifications.first?.workspaceName, "Waiting Workspace")
    }

    /// Verifies a started event clears waiting-for-input state set by a preceding permission prompt.
    func testStartedEventClearsAwaitingInputState() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001183")!,
            title: "Resumed Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001184")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001185")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_010),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .started,
                payload: ""
            )
        )

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertFalse(manager.isWorkspaceAwaitingInput(workspaceId: workspaceId))
        XCTAssertFalse(manager.hasAwaitingInput)
    }

    /// Verifies completed event clears waiting-for-input state as well as marking completion.
    func testCompletedEventClearsAwaitingInputState() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001186")!,
            title: "Completing Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001187")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001188")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_020),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .completed,
                payload: ""
            )
        )

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertFalse(manager.hasAwaitingInput)
    }

    /// Verifies exited event clears waiting-for-input state.
    func testExitedEventClearsAwaitingInputState() {
        let eventMonitor = MockAgentActivityEventMonitor()
        let persistence = InMemoryWorkspacePersistence()
        let manager = makeWorkspaceManager(persistence: persistence, eventMonitor: eventMonitor)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001189")!,
            title: "Exiting Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001190")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001191")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_030),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .exited,
                payload: ""
            )
        )

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertFalse(manager.hasAwaitingInput)
    }

    /// Verifies a Copilot waiting-for-input event (emitted by the reclassified
    /// `notification` hook for a genuine `permission_prompt`) marks the surface as
    /// awaiting input, schedules a Copilot-specific notification, and does not
    /// enqueue a completion — mirroring Claude Code/Codex behaviour for any `AgentType`.
    func testCopilotWaitingForInputEventMarksAwaitingWithoutEnqueuingCompletion() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001192")!,
            title: "Copilot Waiting Surface",
            agentType: .copilot
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001193")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001194")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Copilot Waiting Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_040),
                agentType: .copilot,
                surfaceId: surface.id,
                phase: .waitingForInput,
                payload: ""
            )
        )

        XCTAssertTrue(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertTrue(manager.isWorkspaceAwaitingInput(workspaceId: workspaceId))
        XCTAssertTrue(manager.hasAwaitingInput)
        XCTAssertTrue(manager.pendingCompletionTargets().isEmpty, "Should not enqueue a completion")
        XCTAssertFalse(manager.isWorkspaceWorking(workspaceId: workspaceId))
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)
        XCTAssertEqual(notifications.scheduledNotifications.first?.kind, .waitingForInput)
        XCTAssertEqual(notifications.scheduledNotifications.first?.workspaceName, "Copilot Waiting Workspace")
    }

    /// Verifies two rapid waiting-for-input events for the same surface (e.g. Claude Code's
    /// `PermissionRequest` and `Notification:permission_prompt` hooks firing back-to-back for one
    /// prompt) schedule only a single notification instead of stacking duplicate banners.
    func testDuplicateWaitingForInputEventsScheduleOnlyOneNotification() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001200")!,
            title: "Duplicate Waiting Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001201")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001202")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Duplicate Waiting Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]

        let firstEvent = AgentActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_005_050),
            agentType: .claudeCode,
            surfaceId: surface.id,
            phase: .waitingForInput,
            payload: ""
        )
        let secondEvent = AgentActivityEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_005_051),
            agentType: .claudeCode,
            surfaceId: surface.id,
            phase: .waitingForInput,
            payload: ""
        )
        eventMonitor.emit(firstEvent)
        eventMonitor.emit(secondEvent)

        XCTAssertTrue(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertEqual(notifications.scheduledNotifications.count, 1, "Second duplicate event should not schedule another notification")
        XCTAssertEqual(notifications.removedSurfaceIds, [surface.id], "Only the first, non-duplicate event should touch notification removal")
    }

    /// Verifies an intervening `.started` event between two waiting-for-input events (a genuine
    /// second prompt) is allowed to schedule its own notification, guarding against over-suppression.
    func testStartedBetweenWaitingForInputEventsAllowsSecondNotification() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001203")!,
            title: "Repeated Prompt Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001204")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001205")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Repeated Prompt Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_060),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .waitingForInput,
                payload: ""
            )
        )
        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_061),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .started,
                payload: ""
            )
        )
        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_062),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .waitingForInput,
                payload: ""
            )
        )

        XCTAssertTrue(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertEqual(notifications.scheduledNotifications.count, 2, "A distinct prompt separated by .started should notify again")
    }

    /// Verifies a completed event that follows waiting-for-input directly (no intervening
    /// `.started`) clears the stale "Needs Your Input" notification instead of leaving it to
    /// linger alongside the new "Finished Responding" banner.
    func testWaitingForInputThenCompletedRemovesStaleNotification() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001206")!,
            title: "Waiting Then Completed Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001207")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001208")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Waiting Then Completed Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_070),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .waitingForInput,
                payload: ""
            )
        )
        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_071),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .completed,
                payload: ""
            )
        )

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertEqual(notifications.removedSurfaceIds, [surface.id, surface.id], "Completion should clear the stale waiting notification")
        XCTAssertEqual(notifications.scheduledNotifications.last?.kind, .finished)
    }

    /// Verifies closing a surface while it is awaiting input clears the awaiting-input state
    /// and requests removal of any delivered notification.
    func testClosingSurfaceMidWaitClearsAwaitingInputAndRemovesNotifications() {
        let notifications = MockAgentCompletionNotificationManager()
        let manager = makeWorkspaceManager(notifications: notifications)
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001209")!,
            title: "Closed Mid Wait Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001210")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001211")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Closed Mid Wait Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        manager.closeSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertTrue(notifications.removedSurfaceIds.contains(surface.id))
    }

    /// Verifies an exited event clears any stale "Needs Your Input" notification left behind
    /// when an agent process exits directly from a waiting-for-input state.
    func testExitedEventRemovesStaleNotification() {
        let notifications = MockAgentCompletionNotificationManager()
        let eventMonitor = MockAgentActivityEventMonitor()
        let manager = makeWorkspaceManager(
            notifications: notifications,
            eventMonitor: eventMonitor
        )
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001212")!,
            title: "Exiting While Waiting Surface",
            agentType: .claudeCode
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001213")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001214")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Exiting While Waiting Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: surface.id
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        eventMonitor.emit(
            AgentActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_005_080),
                agentType: .claudeCode,
                surfaceId: surface.id,
                phase: .exited,
                payload: ""
            )
        )

        XCTAssertFalse(manager.awaitingInputSurfaceIds.contains(surface.id))
        XCTAssertTrue(notifications.removedSurfaceIds.contains(surface.id))
    }

    /// Verifies jumpToNextSessionAwaitingInput focuses a surface in the awaiting-input set.
    func testJumpToNextSessionAwaitingInputFocusesAwaitingSurface() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001192")!,
            title: "Awaiting Input"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001193")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001194")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Workspace",
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface], activeSurfaceId: surface.id),
                focusedSurfaceId: nil
            )
        ]
        manager.markSurfaceAwaitingInput(surface.id)

        manager.jumpToNextSessionAwaitingInput()

        XCTAssertEqual(manager.window.selectedWorkspaceId, workspaceId)
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, surface.id)
    }
}
