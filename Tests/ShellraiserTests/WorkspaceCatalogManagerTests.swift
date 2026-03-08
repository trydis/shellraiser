import XCTest
@testable import Shellraiser

/// Covers workspace lifecycle, selection, and repair logic.
final class WorkspaceCatalogManagerTests: WorkspaceTestCase {
    /// Verifies loading with no persisted state creates and selects a default workspace.
    func testLoadWorkspacesCreatesDefaultWorkspaceWhenPersistenceIsEmpty() {
        let persistence = makePersistence()
        let manager = WorkspaceCatalogManager()
        var workspaces: [WorkspaceModel] = []
        var window = WindowModel.initial()

        manager.loadWorkspaces(into: &workspaces, window: &window, persistence: persistence)

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces[0].name, "Workspace")
        XCTAssertEqual(window.selectedWorkspaceId, workspaces[0].id)
        XCTAssertEqual(workspaces[0].focusedSurfaceId, workspaces[0].rootPane.firstActiveSurfaceId())
    }

    /// Verifies loading repairs stale focused-surface state and defaults selection to the first workspace.
    func testLoadWorkspacesRepairsFocusedSurfaceAndInitialSelection() {
        let persistence = makePersistence()
        let manager = WorkspaceCatalogManager()
        let survivingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
            title: "Survivor"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000603")!,
            name: "Recovered",
            rootPane: makeLeaf(paneId: paneId, surfaces: [survivingSurface], activeSurfaceId: survivingSurface.id),
            focusedSurfaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000699")!
        )
        persistence.save([workspace])

        var workspaces: [WorkspaceModel] = []
        var window = WindowModel.initial()
        manager.loadWorkspaces(into: &workspaces, window: &window, persistence: persistence)

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces[0].focusedSurfaceId, survivingSurface.id)
        XCTAssertEqual(workspaces[0].rootPane.firstActiveSurfaceId(), survivingSurface.id)
        XCTAssertEqual(window.selectedWorkspaceId, workspace.id)
    }

    /// Verifies whitespace-only names are ignored during rename mutations.
    func testRenameWorkspaceIgnoresWhitespaceOnlyName() {
        let persistence = makePersistence()
        let manager = WorkspaceCatalogManager()
        var workspaces = [WorkspaceModel.makeDefault(name: "Original")]

        manager.renameWorkspace(
            id: workspaces[0].id,
            name: "   \n",
            workspaces: &workspaces,
            persistence: persistence
        )

        XCTAssertEqual(workspaces[0].name, "Original")
        XCTAssertEqual(persistence.load()?.first?.name, "Original")
    }

    /// Verifies deleting the final workspace recreates a default replacement and selects it.
    func testDeleteWorkspaceRecreatesDefaultWhenDeletingLastWorkspace() {
        let persistence = makePersistence()
        let manager = WorkspaceCatalogManager()
        var workspaces = [WorkspaceModel.makeDefault(name: "Only Workspace")]
        var window = WindowModel(selectedWorkspaceId: workspaces[0].id, isSidebarCollapsed: false)

        manager.deleteWorkspace(
            id: workspaces[0].id,
            workspaces: &workspaces,
            window: &window,
            persistence: persistence
        )

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces[0].name, "Workspace")
        XCTAssertEqual(window.selectedWorkspaceId, workspaces[0].id)
    }

    /// Verifies unread-notification focusing selects the owning workspace and surface.
    func testFocusFirstUnreadNotificationSelectsOwningWorkspaceAndSurface() {
        let persistence = makePersistence()
        let manager = WorkspaceCatalogManager()
        let targetSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            title: "Unread",
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true
        )
        let targetWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            name: "Target",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
                surfaces: [targetSurface],
                activeSurfaceId: targetSurface.id
            ),
            focusedSurfaceId: nil
        )
        var workspaces = [
            WorkspaceModel.makeDefault(name: "First"),
            targetWorkspace
        ]
        var window = WindowModel.initial()

        manager.focusFirstUnreadNotification(
            workspaces: &workspaces,
            window: &window,
            persistence: persistence
        )

        XCTAssertEqual(window.selectedWorkspaceId, targetWorkspace.id)
        XCTAssertEqual(workspaces[1].focusedSurfaceId, targetSurface.id)
        XCTAssertEqual(workspaces[1].rootPane.firstActiveSurfaceId(), targetSurface.id)
    }
}
