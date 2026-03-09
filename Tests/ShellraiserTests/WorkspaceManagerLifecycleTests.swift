import XCTest
@testable import Shellraiser

/// Covers rename/delete request flows and selection helpers on the workspace manager.
@MainActor
final class WorkspaceManagerLifecycleTests: WorkspaceTestCase {
    /// Verifies rename requests target the selected workspace and confirmation mutates persisted state.
    func testRenameRequestConfirmationAndCancellation() {
        let persistence = makePersistence()
        let manager = makeWorkspaceManager(persistence: persistence)
        let workspace = WorkspaceModel.makeDefault(name: "Original")
        manager.workspaces = [workspace]
        manager.window.selectedWorkspaceId = workspace.id

        manager.requestRenameSelectedWorkspace()
        XCTAssertEqual(manager.pendingWorkspaceRename?.workspaceId, workspace.id)
        XCTAssertEqual(manager.pendingWorkspaceRename?.currentName, "Original")

        manager.cancelPendingWorkspaceRename()
        XCTAssertNil(manager.pendingWorkspaceRename)

        manager.requestRenameWorkspace(id: workspace.id)
        manager.confirmPendingWorkspaceRename(name: "Renamed")

        XCTAssertNil(manager.pendingWorkspaceRename)
        XCTAssertEqual(manager.workspaces[0].name, "Renamed")
        XCTAssertEqual(persistence.load()?.first?.name, "Renamed")
    }

    /// Verifies delete requests require confirmation when the workspace still owns active surfaces.
    func testDeleteRequestRequiresConfirmationForActiveWorkspace() {
        let manager = makeWorkspaceManager()
        let workspace = WorkspaceModel.makeDefault(name: "Delete Me")
        manager.workspaces = [workspace]
        manager.window.selectedWorkspaceId = workspace.id

        manager.requestDeleteSelectedWorkspace()

        XCTAssertEqual(manager.pendingWorkspaceDeletion?.workspaceId, workspace.id)
        XCTAssertEqual(manager.pendingWorkspaceDeletion?.workspaceName, "Delete Me")
        XCTAssertEqual(manager.pendingWorkspaceDeletion?.activeProcessCount, 1)

        manager.cancelPendingWorkspaceDeletion()
        XCTAssertNil(manager.pendingWorkspaceDeletion)
        XCTAssertEqual(manager.workspaces.map(\.id), [workspace.id])
    }

    /// Verifies confirming a pending delete removes the workspace and repairs selection.
    func testConfirmPendingWorkspaceDeletionDeletesWorkspace() {
        let manager = makeWorkspaceManager()
        let firstWorkspace = WorkspaceModel.makeDefault(name: "First")
        let secondWorkspace = WorkspaceModel.makeDefault(name: "Second")
        manager.workspaces = [firstWorkspace, secondWorkspace]
        manager.window.selectedWorkspaceId = secondWorkspace.id

        manager.requestDeleteWorkspace(id: secondWorkspace.id)
        manager.confirmPendingWorkspaceDeletion()

        XCTAssertNil(manager.pendingWorkspaceDeletion)
        XCTAssertEqual(manager.workspaces.map(\.id), [firstWorkspace.id])
        XCTAssertEqual(manager.window.selectedWorkspaceId, firstWorkspace.id)
    }

    /// Verifies empty workspaces bypass confirmation and delete immediately.
    func testDeleteRequestImmediatelyDeletesWorkspaceWithoutActiveSurfaces() {
        let manager = makeWorkspaceManager()
        let emptyWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001301")!,
            name: "Empty",
            rootPane: .leaf(.empty()),
            focusedSurfaceId: nil
        )
        let fallbackWorkspace = WorkspaceModel.makeDefault(name: "Fallback")
        manager.workspaces = [emptyWorkspace, fallbackWorkspace]
        manager.window.selectedWorkspaceId = emptyWorkspace.id

        manager.requestDeleteWorkspace(id: emptyWorkspace.id)

        XCTAssertNil(manager.pendingWorkspaceDeletion)
        XCTAssertEqual(manager.workspaces.map(\.id), [fallbackWorkspace.id])
        XCTAssertEqual(manager.window.selectedWorkspaceId, fallbackWorkspace.id)
    }

    /// Verifies display-index helpers respect the 1-based workspace ordering.
    func testWorkspaceDisplayIndexHelpersSelectWithinBounds() {
        let manager = makeWorkspaceManager()
        let first = WorkspaceModel.makeDefault(name: "One")
        let second = WorkspaceModel.makeDefault(name: "Two")
        manager.workspaces = [first, second]

        XCTAssertTrue(manager.hasWorkspace(atDisplayIndex: 1))
        XCTAssertTrue(manager.hasWorkspace(atDisplayIndex: 2))
        XCTAssertFalse(manager.hasWorkspace(atDisplayIndex: 0))
        XCTAssertFalse(manager.hasWorkspace(atDisplayIndex: 3))

        manager.selectWorkspace(atDisplayIndex: 2)
        XCTAssertEqual(manager.window.selectedWorkspaceId, second.id)

        manager.selectWorkspace(atDisplayIndex: 3)
        XCTAssertEqual(manager.window.selectedWorkspaceId, second.id)
    }

    /// Verifies selecting a workspace repairs its focused-surface state before subsequent focus flows.
    func testSelectWorkspaceRepairsFocusedSurfaceState() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001321")!,
            title: "Recovered"
        )
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001322")!,
            name: "Recovered",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001323")!,
                surfaces: [surface],
                activeSurfaceId: surface.id
            ),
            focusedSurfaceId: nil
        )
        manager.workspaces = [workspace]

        manager.selectWorkspace(workspace.id)

        XCTAssertEqual(manager.window.selectedWorkspaceId, workspace.id)
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, surface.id)
        XCTAssertEqual(manager.workspaces[0].rootPane.firstActiveSurfaceId(), surface.id)
    }
}
