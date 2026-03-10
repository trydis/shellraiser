import XCTest
@testable import Shellraiser

/// Covers AppleScript-oriented workspace and split behavior.
@MainActor
final class WorkspaceManagerAppleScriptTests: WorkspaceTestCase {
    /// Verifies creating a workspace with a scripted name applies that name to workspace state.
    func testNewWorkspaceAppliesProvidedName() {
        let manager = makeWorkspaceManager()
        manager.hasLoadedPersistedWorkspaces = true
        ShellraiserScriptingController.shared.install(workspaceManager: manager)

        guard let workspace = ShellraiserScriptingController.shared.newWorkspace(
            name: "Review Session",
            configuration: nil
        ) else {
            return XCTFail("Expected scripted workspace creation to succeed.")
        }

        XCTAssertEqual(workspace.name, "Review Session")
        XCTAssertEqual(manager.workspaces.first?.name, "Review Session")
    }

    /// Verifies scripted workspace creation preserves the default name when no name is provided.
    func testNewWorkspaceUsesDefaultNameWhenNotProvided() {
        let manager = makeWorkspaceManager()
        manager.hasLoadedPersistedWorkspaces = true
        ShellraiserScriptingController.shared.install(workspaceManager: manager)

        guard let workspace = ShellraiserScriptingController.shared.newWorkspace(
            name: nil,
            configuration: nil
        ) else {
            return XCTFail("Expected scripted workspace creation to succeed.")
        }

        XCTAssertEqual(workspace.name, "Workspace")
        XCTAssertEqual(manager.workspaces.first?.name, "Workspace")
    }

    /// Verifies creating a workspace with a scripted surface configuration applies its working directory.
    func testNewWorkspaceAppliesSurfaceConfigurationWorkingDirectory() {
        let manager = makeWorkspaceManager()
        manager.hasLoadedPersistedWorkspaces = true
        ShellraiserScriptingController.shared.install(workspaceManager: manager)

        let configuration = ScriptableSurfaceConfiguration()
        configuration.initialWorkingDirectory = "/tmp/project"

        guard let workspace = ShellraiserScriptingController.shared.newWorkspace(
            configuration: configuration
        ) else {
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

    /// Verifies script directions map onto the expected split orientation and pane side.
    func testSplitScriptTerminalMapsDirectionsToExpectedPlacement() {
        let manager = makeWorkspaceManager()
        let rightSource = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
            title: "Right Source"
        )
        let leftSource = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
            title: "Left Source"
        )
        let downSource = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!,
            title: "Down Source"
        )
        let upSource = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000904")!,
            title: "Up Source"
        )

        manager.workspaces = [
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000905")!,
                rootPane: makeLeaf(
                    paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000906")!,
                    surfaces: [rightSource]
                ),
                focusedSurfaceId: rightSource.id
            ),
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000907")!,
                rootPane: makeLeaf(
                    paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000908")!,
                    surfaces: [leftSource]
                ),
                focusedSurfaceId: leftSource.id
            ),
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000909")!,
                rootPane: makeLeaf(
                    paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000910")!,
                    surfaces: [downSource]
                ),
                focusedSurfaceId: downSource.id
            ),
            makeWorkspace(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000911")!,
                rootPane: makeLeaf(
                    paneId: UUID(uuidString: "00000000-0000-0000-0000-000000000912")!,
                    surfaces: [upSource]
                ),
                focusedSurfaceId: upSource.id
            )
        ]

        guard let rightTerminal = manager.splitScriptTerminal(
            surfaceId: rightSource.id,
            direction: "right",
            configuration: nil
        ), let leftTerminal = manager.splitScriptTerminal(
            surfaceId: leftSource.id,
            direction: "left",
            configuration: nil
        ), let downTerminal = manager.splitScriptTerminal(
            surfaceId: downSource.id,
            direction: "down",
            configuration: nil
        ), let upTerminal = manager.splitScriptTerminal(
            surfaceId: upSource.id,
            direction: "up",
            configuration: nil
        ) else {
            return XCTFail("Expected script splits in every direction to create terminals.")
        }

        guard case .split(let rightSplit) = manager.workspaces[0].rootPane else {
            return XCTFail("Expected right-directed script split to create a split node.")
        }
        XCTAssertEqual(rightSplit.orientation, .horizontal)
        XCTAssertEqual(rightSplit.first.allSurfaceIds(), [rightSource.id])
        XCTAssertEqual(rightSplit.second.allSurfaceIds(), [UUID(uuidString: rightTerminal.id)!])

        guard case .split(let leftSplit) = manager.workspaces[1].rootPane else {
            return XCTFail("Expected left-directed script split to create a split node.")
        }
        XCTAssertEqual(leftSplit.orientation, .horizontal)
        XCTAssertEqual(leftSplit.first.allSurfaceIds(), [UUID(uuidString: leftTerminal.id)!])
        XCTAssertEqual(leftSplit.second.allSurfaceIds(), [leftSource.id])

        guard case .split(let downSplit) = manager.workspaces[2].rootPane else {
            return XCTFail("Expected down-directed script split to create a split node.")
        }
        XCTAssertEqual(downSplit.orientation, .vertical)
        XCTAssertEqual(downSplit.first.allSurfaceIds(), [downSource.id])
        XCTAssertEqual(downSplit.second.allSurfaceIds(), [UUID(uuidString: downTerminal.id)!])

        guard case .split(let upSplit) = manager.workspaces[3].rootPane else {
            return XCTFail("Expected up-directed script split to create a split node.")
        }
        XCTAssertEqual(upSplit.orientation, .vertical)
        XCTAssertEqual(upSplit.first.allSurfaceIds(), [UUID(uuidString: upTerminal.id)!])
        XCTAssertEqual(upSplit.second.allSurfaceIds(), [upSource.id])
    }
}
