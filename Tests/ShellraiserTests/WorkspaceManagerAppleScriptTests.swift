import XCTest
@testable import Shellraiser

/// Covers AppleScript-oriented workspace and split behavior.
@MainActor
final class WorkspaceManagerAppleScriptTests: WorkspaceTestCase {
    /// Verifies creating a workspace with a scripted surface configuration applies its working directory.
    func testNewWorkspaceAppliesSurfaceConfigurationWorkingDirectory() {
        let manager = makeWorkspaceManager()
        manager.hasLoadedPersistedWorkspaces = true
        ShellraiserScriptingController.shared.install(workspaceManager: manager)

        let configuration = ScriptableSurfaceConfiguration()
        configuration.initialWorkingDirectory = "/tmp/project"

        guard let workspace = ShellraiserScriptingController.shared.newWorkspace(configuration: configuration) else {
            return XCTFail("Expected scripted workspace creation to succeed.")
        }

        guard let terminal = workspace.selectedTab?.terminals.first else {
            return XCTFail("Expected scripted workspace to expose its initial terminal.")
        }

        XCTAssertEqual(terminal.workingDirectory, "/tmp/project")
        XCTAssertEqual(manager.workspaces.first?.rootPane.firstActiveSurfaceId(), UUID(uuidString: terminal.id))

        guard let surfaceId = UUID(uuidString: terminal.id),
              let createdSurface = surface(in: manager.workspaces[0].rootPane, surfaceId: surfaceId) else {
            return XCTFail("Expected workspace state to contain the created terminal surface.")
        }

        XCTAssertEqual(createdSurface.terminalConfig.workingDirectory, "/tmp/project")
    }

    /// Verifies unique-id terminal resolution survives later pane mutations that reorder terminal snapshots.
    func testTerminalUniqueIDResolutionRemainsStableAfterAdditionalSplits() {
        let manager = makeWorkspaceManager()
        manager.hasLoadedPersistedWorkspaces = true
        ShellraiserScriptingController.shared.install(workspaceManager: manager)

        let topLeftSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000900")!,
            title: "Top Left"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [topLeftSurface]),
                focusedSurfaceId: topLeftSurface.id
            )
        ]

        guard let topRight = manager.splitScriptTerminal(
            surfaceId: topLeftSurface.id,
            direction: "right",
            configuration: nil
        ) else {
            return XCTFail("Expected script split to create the top-right terminal.")
        }

        let delegate = ShellraiserAppDelegate()
        XCTAssertEqual(delegate.valueInTerminals(withUniqueID: topRight.id)?.id, topRight.id)

        guard let bottomLeft = manager.splitScriptTerminal(
            surfaceId: topLeftSurface.id,
            direction: "down",
            configuration: nil
        ) else {
            return XCTFail("Expected second script split to create the bottom-left terminal.")
        }

        XCTAssertEqual(delegate.valueInTerminals(withUniqueID: topRight.id)?.id, topRight.id)
        XCTAssertEqual(delegate.valueInTerminals(withUniqueID: bottomLeft.id)?.id, bottomLeft.id)
    }

    /// Verifies script directions map onto the expected side-by-side and stacked pane layouts.
    func testSplitScriptTerminalMapsDirectionsToExpectedOrientations() {
        let manager = makeWorkspaceManager()
        let existingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
            title: "Existing"
        )
        let horizontalPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let verticalPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        let horizontalWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let verticalWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000905")!

        manager.workspaces = [
            makeWorkspace(
                id: horizontalWorkspaceId,
                rootPane: makeLeaf(paneId: horizontalPaneId, surfaces: [existingSurface]),
                focusedSurfaceId: existingSurface.id
            ),
            makeWorkspace(
                id: verticalWorkspaceId,
                rootPane: makeLeaf(
                    paneId: verticalPaneId,
                    surfaces: [makeSurface(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000906")!,
                        title: "Existing Vertical"
                    )]
                ),
                focusedSurfaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000906")!
            )
        ]

        _ = manager.splitScriptTerminal(
            surfaceId: existingSurface.id,
            direction: "right",
            configuration: nil
        )

        guard case .split(let horizontalSplit) = manager.workspaces[0].rootPane else {
            return XCTFail("Expected right-directed script split to create a split node.")
        }
        XCTAssertEqual(horizontalSplit.orientation, .horizontal)

        let verticalSourceSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000906")!
        _ = manager.splitScriptTerminal(
            surfaceId: verticalSourceSurfaceId,
            direction: "down",
            configuration: nil
        )

        guard case .split(let verticalSplit) = manager.workspaces[1].rootPane else {
            return XCTFail("Expected down-directed script split to create a split node.")
        }
        XCTAssertEqual(verticalSplit.orientation, .vertical)
    }
}
