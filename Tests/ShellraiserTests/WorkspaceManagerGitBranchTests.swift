import XCTest
@testable import Shellraiser

/// Covers manager-owned Git state caching for focused workspace surfaces.
@MainActor
final class WorkspaceManagerGitBranchTests: WorkspaceTestCase {
    /// Verifies the sidebar resolves Git state from the workspace's focused surface.
    func testFocusedGitStateUsesFocusedSurface() {
        let manager = makeWorkspaceManager()
        let firstSurface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001301")!, title: "One")
        let secondSurface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001302")!, title: "Two")
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001303")!,
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001304")!,
                surfaces: [firstSurface, secondSurface],
                activeSurfaceId: secondSurface.id
            ),
            focusedSurfaceId: secondSurface.id
        )
        manager.workspaces = [workspace]
        manager.gitStatesBySurfaceId = [
            firstSurface.id: ResolvedGitState(branchName: "main", isLinkedWorktree: false),
            secondSurface.id: ResolvedGitState(branchName: "feature/sidebar", isLinkedWorktree: true)
        ]

        XCTAssertEqual(
            manager.focusedGitState(workspaceId: workspace.id),
            ResolvedGitState(branchName: "feature/sidebar", isLinkedWorktree: true)
        )
    }

    /// Verifies closing a surface clears its cached Git state.
    func testCloseSurfaceClearsCachedGitState() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001311")!)
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001312")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001313")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]
        manager.gitStatesBySurfaceId = [
            surface.id: ResolvedGitState(branchName: "main", isLinkedWorktree: false)
        ]

        manager.closeSurface(workspaceId: workspaceId, paneId: paneId, surfaceId: surface.id)

        XCTAssertNil(manager.gitStatesBySurfaceId[surface.id])
    }

    /// Verifies deleting a workspace clears cached Git state for its released surfaces.
    func testDeleteWorkspaceClearsCachedGitState() {
        let manager = makeWorkspaceManager()
        let surface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001314")!)
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001315")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001316")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]
        manager.window.selectedWorkspaceId = workspaceId
        manager.gitStatesBySurfaceId = [
            surface.id: ResolvedGitState(branchName: "main", isLinkedWorktree: false)
        ]

        manager.deleteWorkspace(id: workspaceId)

        XCTAssertNil(manager.gitStatesBySurfaceId[surface.id])
    }

    /// Verifies manager-level pwd updates normalize the path before persisting and refreshing Git state.
    func testSetSurfaceWorkingDirectoryNormalizesPathBeforeRefreshingGitState() throws {
        let normalizedWorkingDirectory = "/tmp/repo"
        let expectedState = ResolvedGitState(branchName: "main", isLinkedWorktree: false)
        let manager = makeWorkspaceManager(
            gitStateResolver: { workingDirectory in
                workingDirectory == normalizedWorkingDirectory ? expectedState : nil
            }
        )
        let surface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001321")!)
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001322")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001323")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        let refreshTask = manager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workingDirectory: "\(normalizedWorkingDirectory)\n"
        )

        XCTAssertEqual(
            manager.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)?.terminalConfig.workingDirectory,
            normalizedWorkingDirectory
        )

        let refreshCompleted = expectation(description: "Git refresh completes")
        Task.detached {
            await refreshTask?.value
            refreshCompleted.fulfill()
        }

        wait(for: [refreshCompleted], timeout: 1.0)

        XCTAssertEqual(manager.gitStatesBySurfaceId[surface.id], expectedState)
    }
}
