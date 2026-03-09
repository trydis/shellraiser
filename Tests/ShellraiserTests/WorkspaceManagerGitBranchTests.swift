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
}
