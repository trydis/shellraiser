import XCTest
@testable import Shellraiser

/// Covers command routing, menu labeling, and palette state in the workspace manager.
@MainActor
final class WorkspaceManagerCommandTests: WorkspaceTestCase {
    /// Verifies close-item titles distinguish between closing a whole pane and a single tab.
    func testCloseItemTitleReflectsSinglePaneVersusTabContext() {
        let manager = makeWorkspaceManager()
        let firstSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001201")!,
            title: "First"
        )
        let secondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001202")!,
            title: "Second"
        )
        let singlePaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001203")!
        let multiPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001204")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001205")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Commands",
                rootPane: .split(
                    PaneSplitModel(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001206")!,
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: makeLeaf(paneId: singlePaneId, surfaces: [firstSurface], activeSurfaceId: firstSurface.id),
                        second: makeLeaf(paneId: multiPaneId, surfaces: [firstSurface, secondSurface], activeSurfaceId: firstSurface.id)
                    )
                ),
                focusedSurfaceId: firstSurface.id
            )
        ]

        XCTAssertEqual(
            manager.closeItemTitle(workspaceId: workspaceId, paneId: singlePaneId),
            "Close Active Pane"
        )
        XCTAssertEqual(
            manager.closeItemTitle(workspaceId: workspaceId, paneId: multiPaneId),
            "Close Active Tab"
        )
        XCTAssertEqual(
            manager.closeItemTitle(workspaceId: workspaceId, paneId: singlePaneId, surfaceId: firstSurface.id),
            "Close Active Tab"
        )
    }

    /// Verifies pane command availability tracks split adjacency and tab counts.
    func testCanPerformPaneCommandReflectsPaneState() {
        let manager = makeWorkspaceManager()
        let leftSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001211")!,
            title: "Left"
        )
        let rightSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001212")!,
            title: "Right"
        )
        let rightSecondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001213")!,
            title: "Right 2"
        )
        let leftPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001214")!
        let rightPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001215")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001216")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Commands",
                rootPane: .split(
                    PaneSplitModel(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001217")!,
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: makeLeaf(paneId: leftPaneId, surfaces: [leftSurface], activeSurfaceId: leftSurface.id),
                        second: makeLeaf(
                            paneId: rightPaneId,
                            surfaces: [rightSurface, rightSecondSurface],
                            activeSurfaceId: rightSurface.id
                        )
                    )
                ),
                focusedSurfaceId: leftSurface.id
            )
        ]

        XCTAssertTrue(manager.canPerformPaneCommand(.newSurface, workspaceId: workspaceId, paneId: leftPaneId))
        XCTAssertTrue(manager.canPerformPaneCommand(.split(.vertical), workspaceId: workspaceId, paneId: leftPaneId))
        XCTAssertTrue(manager.canPerformPaneCommand(.focus(.right), workspaceId: workspaceId, paneId: leftPaneId))
        XCTAssertFalse(manager.canPerformPaneCommand(.focus(.left), workspaceId: workspaceId, paneId: leftPaneId))
        XCTAssertFalse(manager.canPerformPaneCommand(.nextSurface, workspaceId: workspaceId, paneId: leftPaneId))
        XCTAssertTrue(manager.canPerformPaneCommand(.nextSurface, workspaceId: workspaceId, paneId: rightPaneId))
        XCTAssertFalse(
            manager.canPerformPaneCommand(
                .closeActiveItem,
                workspaceId: workspaceId,
                paneId: leftPaneId,
                surfaceId: rightSurface.id
            )
        )
    }

    /// Verifies explicit pane commands cycle tabs with wraparound and move focus between panes.
    func testPerformPaneCommandCyclesTabsAndMovesPaneFocus() {
        let notifications = MockAgentCompletionNotificationManager()
        let manager = makeWorkspaceManager(notifications: notifications)
        let leftSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001221")!,
            title: "Left"
        )
        let rightFirstSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001222")!,
            title: "Right 1"
        )
        let rightSecondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001223")!,
            title: "Right 2",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 3,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_005_100)
        )
        let leftPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001224")!
        let rightPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001225")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001226")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Commands",
                rootPane: .split(
                    PaneSplitModel(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001227")!,
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: makeLeaf(paneId: leftPaneId, surfaces: [leftSurface], activeSurfaceId: leftSurface.id),
                        second: makeLeaf(
                            paneId: rightPaneId,
                            surfaces: [rightFirstSurface, rightSecondSurface],
                            activeSurfaceId: rightFirstSurface.id
                        )
                    )
                ),
                focusedSurfaceId: rightFirstSurface.id
            )
        ]
        manager.window.selectedWorkspaceId = workspaceId

        XCTAssertTrue(
            manager.performPaneCommand(
                .nextSurface,
                workspaceId: workspaceId,
                paneId: rightPaneId,
                surfaceId: rightFirstSurface.id
            )
        )
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, rightSecondSurface.id)
        XCTAssertFalse(surface(in: manager.workspaces[0].rootPane, surfaceId: rightSecondSurface.id)?.hasPendingCompletion ?? true)
        XCTAssertEqual(notifications.removedSurfaceIds, [rightSecondSurface.id])

        XCTAssertTrue(
            manager.performPaneCommand(
                .previousSurface,
                workspaceId: workspaceId,
                paneId: rightPaneId,
                surfaceId: rightFirstSurface.id
            )
        )
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, rightSecondSurface.id)

        XCTAssertTrue(manager.performPaneCommand(.focus(.left), workspaceId: workspaceId, paneId: rightPaneId))
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, leftSurface.id)
    }

    /// Verifies app-driven pane splits inherit the source surface's tracked cwd.
    func testPerformPaneCommandSplitInheritsSourceSurfaceWorkingDirectory() {
        let manager = makeWorkspaceManager()
        var sourceSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001231")!,
            title: "Source"
        )
        sourceSurface.terminalConfig.workingDirectory = "/tmp/project"

        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001232")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001233")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Split",
                rootPane: makeLeaf(paneId: paneId, surfaces: [sourceSurface], activeSurfaceId: sourceSurface.id),
                focusedSurfaceId: sourceSurface.id
            )
        ]

        XCTAssertTrue(
            manager.performPaneCommand(
                .split(.horizontal),
                workspaceId: workspaceId,
                paneId: paneId,
                surfaceId: sourceSurface.id
            )
        )

        guard case .split(let split) = manager.workspaces[0].rootPane else {
            return XCTFail("Expected split command to create a split node.")
        }
        guard let createdSurfaceId = split.second.firstActiveSurfaceId(),
              let createdSurface = surface(in: manager.workspaces[0].rootPane, surfaceId: createdSurfaceId) else {
            return XCTFail("Expected split command to create a focused surface.")
        }

        XCTAssertEqual(createdSurface.terminalConfig.workingDirectory, "/tmp/project")
    }

    /// Verifies app-driven pane splits fall back to the home directory when no usable cwd is tracked.
    func testPerformPaneCommandSplitFallsBackToHomeDirectoryForBlankWorkingDirectory() {
        let manager = makeWorkspaceManager()
        var sourceSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001241")!,
            title: "Blank Source"
        )
        sourceSurface.terminalConfig.workingDirectory = "   \n\t  "

        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001242")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001243")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Split",
                rootPane: makeLeaf(paneId: paneId, surfaces: [sourceSurface], activeSurfaceId: sourceSurface.id),
                focusedSurfaceId: sourceSurface.id
            )
        ]

        XCTAssertTrue(
            manager.performPaneCommand(
                .split(.vertical),
                workspaceId: workspaceId,
                paneId: paneId,
                surfaceId: sourceSurface.id
            )
        )

        guard case .split(let split) = manager.workspaces[0].rootPane else {
            return XCTFail("Expected split command to create a split node.")
        }
        guard let createdSurfaceId = split.second.firstActiveSurfaceId(),
              let createdSurface = surface(in: manager.workspaces[0].rootPane, surfaceId: createdSurfaceId) else {
            return XCTFail("Expected split command to create a focused surface.")
        }

        XCTAssertEqual(createdSurface.terminalConfig.workingDirectory, NSHomeDirectory())
    }

    /// Verifies an explicit source surface with blank cwd does not borrow cwd from another active tab in the pane.
    func testPerformPaneCommandSplitDoesNotUseActivePaneSurfaceWhenExplicitSourceCwdIsBlank() {
        let manager = makeWorkspaceManager()
        var blankSourceSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001251")!,
            title: "Blank Source"
        )
        blankSourceSurface.terminalConfig.workingDirectory = "   \n\t  "

        var activeSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001252")!,
            title: "Active"
        )
        activeSurface.terminalConfig.workingDirectory = "/tmp/active-pane"

        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001253")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001254")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Split",
                rootPane: makeLeaf(
                    paneId: paneId,
                    surfaces: [blankSourceSurface, activeSurface],
                    activeSurfaceId: activeSurface.id
                ),
                focusedSurfaceId: blankSourceSurface.id
            )
        ]

        XCTAssertTrue(
            manager.performPaneCommand(
                .split(.horizontal),
                workspaceId: workspaceId,
                paneId: paneId,
                surfaceId: blankSourceSurface.id
            )
        )

        guard case .split(let split) = manager.workspaces[0].rootPane else {
            return XCTFail("Expected split command to create a split node.")
        }
        guard let createdSurfaceId = split.second.firstActiveSurfaceId(),
              let createdSurface = surface(in: manager.workspaces[0].rootPane, surfaceId: createdSurfaceId) else {
            return XCTFail("Expected split command to create a focused surface.")
        }

        XCTAssertEqual(createdSurface.terminalConfig.workingDirectory, NSHomeDirectory())
    }

    /// Verifies command palette state reflects selection, pending completions, and workspace switch limits.
    func testCommandPaletteItemsReflectWorkspaceState() {
        let manager = makeWorkspaceManager()
        manager.workspaces = (1...10).map { index in
            let surface = makeSurface(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                title: "Surface \(index)"
            )
            return makeWorkspace(
                name: "Workspace \(index)",
                rootPane: makeLeaf(surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        }

        let itemsWithoutSelection = manager.commandPaletteItems()
        XCTAssertEqual(itemsWithoutSelection.filter { $0.id.hasPrefix("workspace.switch.") }.count, 9)
        XCTAssertFalse(itemsWithoutSelection.first(where: { $0.id == "workspace.rename" })?.isEnabled ?? true)
        XCTAssertFalse(itemsWithoutSelection.first(where: { $0.id == "workspace.next-completion" })?.isEnabled ?? true)

        manager.window.selectedWorkspaceId = manager.workspaces[0].id
        let pendingSurfaceId = manager.workspaces[1].focusedSurfaceId!
        let pendingPaneId = manager.workspaces[1].rootPane.firstLeafId()!
        _ = manager.surfaceManager.markPendingCompletion(
            workspaceId: manager.workspaces[1].id,
            surfaceId: pendingSurfaceId,
            agentType: .codex,
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_005_300),
            workspaces: &manager.workspaces,
            persistence: manager.persistence
        )

        let itemsWithSelection = manager.commandPaletteItems()
        XCTAssertTrue(itemsWithSelection.first(where: { $0.id == "workspace.rename" })?.isEnabled ?? false)
        XCTAssertTrue(itemsWithSelection.first(where: { $0.id == "workspace.next-completion" })?.isEnabled ?? false)
        XCTAssertEqual(manager.pendingCompletionQueuePosition(workspaceId: manager.workspaces[1].id, paneId: pendingPaneId)?.position, 1)
    }
}
