import XCTest
@testable import Shellraiser

/// Covers selected-workspace focus trigger logic used by `WorkspaceView`.
final class WorkspaceViewFocusLogicTests: XCTestCase {
    /// Verifies focus is requested only for the currently selected workspace.
    func testShouldRequestFocusMatchesSelectedWorkspace() {
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001331")!
        let otherWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001332")!

        XCTAssertTrue(
            WorkspaceViewFocusLogic.shouldRequestFocus(
                selectedWorkspaceId: workspaceId,
                workspaceId: workspaceId
            )
        )
        XCTAssertFalse(
            WorkspaceViewFocusLogic.shouldRequestFocus(
                selectedWorkspaceId: otherWorkspaceId,
                workspaceId: workspaceId
            )
        )
        XCTAssertFalse(
            WorkspaceViewFocusLogic.shouldRequestFocus(
                selectedWorkspaceId: nil,
                workspaceId: workspaceId
            )
        )
    }

    /// Verifies the first-appearance refresh only triggers a restore when a pending flag exists.
    func testShouldRestoreFocusAfterLayoutRefreshConsumesPendingState() {
        XCTAssertTrue(
            WorkspaceViewFocusLogic.shouldRestoreFocusAfterLayoutRefresh(pendingRestore: true)
        )
        XCTAssertFalse(
            WorkspaceViewFocusLogic.shouldRestoreFocusAfterLayoutRefresh(pendingRestore: false)
        )
    }
}
