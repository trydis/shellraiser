import XCTest
@testable import Shellraiser

/// Covers pane and tab mutation behavior in the surface manager.
final class WorkspaceSurfaceManagerPaneOperationsTests: WorkspaceTestCase {
    /// Verifies adding a surface appends it to the target pane, focuses it, and persists the mutation.
    func testAddSurfaceAppendsToPaneAndFocusesNewSurface() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let existingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
            title: "Existing"
        )
        let newSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
            title: "New"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000803")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000804")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [existingSurface]),
                focusedSurfaceId: existingSurface.id
            )
        ]

        let didAdd = manager.addSurface(
            workspaceId: workspaceId,
            paneId: paneId,
            surface: newSurface,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertTrue(didAdd)
        XCTAssertEqual(workspaces[0].rootPane.surfaceIds(in: paneId), [existingSurface.id, newSurface.id])
        XCTAssertEqual(workspaces[0].focusedSurfaceId, newSurface.id)
        XCTAssertEqual(persistence.load(), workspaces)
    }

    /// Verifies closing the last tab in a pane compacts the split, clears stale zoom, and advances focus.
    func testCloseSurfaceCompactsSplitAndClearsStaleZoom() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let closingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000811")!,
            title: "Close Me"
        )
        let survivorSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000812")!,
            title: "Keep Me"
        )
        let closingPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000813")!
        let survivorPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000814")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000815")!
        let rootPane = PaneNodeModel.split(
            PaneSplitModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000816")!,
                orientation: .horizontal,
                ratio: 0.5,
                first: makeLeaf(paneId: closingPaneId, surfaces: [closingSurface]),
                second: makeLeaf(paneId: survivorPaneId, surfaces: [survivorSurface])
            )
        )
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: rootPane,
                focusedSurfaceId: closingSurface.id,
                zoomedPaneId: closingPaneId
            )
        ]

        manager.closeSurface(
            workspaceId: workspaceId,
            paneId: closingPaneId,
            surfaceId: closingSurface.id,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertEqual(workspaces[0].rootPane, makeLeaf(paneId: survivorPaneId, surfaces: [survivorSurface]))
        XCTAssertEqual(workspaces[0].focusedSurfaceId, survivorSurface.id)
        XCTAssertNil(workspaces[0].zoomedPaneId)
        XCTAssertEqual(persistence.load(), workspaces)
    }

    /// Verifies splitting a pane creates a new surface and focuses it.
    func testSplitPaneCreatesNewSurfaceAndFocusesIt() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let existingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000821")!,
            title: "Existing"
        )
        let createdSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000822")!,
            title: "Created"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000823")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000824")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [existingSurface]),
                focusedSurfaceId: existingSurface.id
            )
        ]

        let newSurfaceId = manager.splitPane(
            workspaceId: workspaceId,
            paneId: paneId,
            orientation: .vertical,
            newSurface: createdSurface,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertEqual(newSurfaceId, createdSurface.id)
        XCTAssertEqual(workspaces[0].focusedSurfaceId, createdSurface.id)

        guard case .split(let split) = workspaces[0].rootPane else {
            return XCTFail("Expected workspace root pane to become a split.")
        }

        XCTAssertEqual(split.orientation, .vertical)
        XCTAssertEqual(split.first.paneNode(id: paneId), makeLeaf(paneId: paneId, surfaces: [existingSurface]))
        XCTAssertEqual(split.second.allSurfaceIds(), [createdSurface.id])
    }

    /// Verifies splitting can insert the new pane before the existing pane when requested.
    func testSplitPaneCanInsertNewSurfaceAsFirstChild() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let existingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000825")!,
            title: "Existing"
        )
        let createdSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000826")!,
            title: "Created"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000827")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000828")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [existingSurface]),
                focusedSurfaceId: existingSurface.id
            )
        ]

        let newSurfaceId = manager.splitPane(
            workspaceId: workspaceId,
            paneId: paneId,
            orientation: .horizontal,
            position: .first,
            newSurface: createdSurface,
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertEqual(newSurfaceId, createdSurface.id)
        XCTAssertEqual(workspaces[0].focusedSurfaceId, createdSurface.id)

        guard case .split(let split) = workspaces[0].rootPane else {
            return XCTFail("Expected workspace root pane to become a split.")
        }

        XCTAssertEqual(split.orientation, .horizontal)
        XCTAssertEqual(split.first.allSurfaceIds(), [createdSurface.id])
        XCTAssertEqual(split.second.paneNode(id: paneId), makeLeaf(paneId: paneId, surfaces: [existingSurface]))
    }

    /// Verifies zoom toggling only acts on existing panes and round-trips back to nil.
    func testTogglePaneZoomTogglesExistingPaneAndIgnoresUnknownPane() {
        let persistence = makePersistence()
        let manager = WorkspaceSurfaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000831")!,
            title: "Only"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000832")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000833")!
        var workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        manager.togglePaneZoom(
            workspaceId: workspaceId,
            paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000899")!,
            workspaces: &workspaces,
            persistence: persistence
        )
        XCTAssertNil(workspaces[0].zoomedPaneId)

        manager.togglePaneZoom(
            workspaceId: workspaceId,
            paneId: paneId,
            workspaces: &workspaces,
            persistence: persistence
        )
        XCTAssertEqual(workspaces[0].zoomedPaneId, paneId)

        manager.togglePaneZoom(
            workspaceId: workspaceId,
            paneId: paneId,
            workspaces: &workspaces,
            persistence: persistence
        )
        XCTAssertNil(workspaces[0].zoomedPaneId)
    }
}
