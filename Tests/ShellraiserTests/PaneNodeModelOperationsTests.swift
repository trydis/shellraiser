import XCTest
@testable import Shellraiser

/// Covers pane-tree mutation and navigation behavior.
final class PaneNodeModelOperationsTests: XCTestCase {
    /// Verifies leaf splitting preserves the original leaf and activates the new surface.
    func testSplitLeafReplacesTargetLeafWithSplitAndActivatesNewSurface() {
        let existingSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000101"), title: "Existing")
        let newSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000102"), title: "New")
        let originalLeaf = PaneLeafModel(
            id: uuid("00000000-0000-0000-0000-000000000001"),
            surfaces: [existingSurface],
            activeSurfaceId: existingSurface.id
        )
        var tree = PaneNodeModel.leaf(originalLeaf)

        let createdSurfaceId = tree.splitLeaf(
            paneId: originalLeaf.id,
            orientation: .horizontal,
            newSurface: newSurface
        )

        XCTAssertEqual(createdSurfaceId, newSurface.id)

        guard case .split(let split) = tree else {
            return XCTFail("Expected split node after splitting a leaf.")
        }

        XCTAssertEqual(split.orientation, .horizontal)
        XCTAssertEqual(split.ratio, 0.5)
        XCTAssertEqual(split.first, .leaf(originalLeaf))

        guard case .leaf(let secondLeaf) = split.second else {
            return XCTFail("Expected the second child to be a leaf.")
        }

        XCTAssertEqual(secondLeaf.surfaces, [newSurface])
        XCTAssertEqual(secondLeaf.activeSurfaceId, newSurface.id)
    }

    /// Verifies active tab fallback is repaired when the active surface is closed.
    func testRemoveSurfacePromotesFirstRemainingSurfaceWhenActiveSurfaceIsRemoved() {
        let firstSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000201"), title: "First")
        let activeSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000202"), title: "Active")
        let thirdSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000203"), title: "Third")
        let paneId = uuid("00000000-0000-0000-0000-000000000002")
        var tree = PaneNodeModel.leaf(
            PaneLeafModel(
                id: paneId,
                surfaces: [firstSurface, activeSurface, thirdSurface],
                activeSurfaceId: activeSurface.id
            )
        )

        let didRemove = tree.removeSurface(from: paneId, surfaceId: activeSurface.id)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(tree.surfaceIds(in: paneId), [firstSurface.id, thirdSurface.id])
        XCTAssertEqual(tree.activeSurfaceId(in: paneId), firstSurface.id)
    }

    /// Verifies compacting an empty child collapses the split into the surviving pane.
    func testCompactEmptyLeavesPromotesNonEmptySibling() {
        let survivingSurface = makeSurface(id: uuid("00000000-0000-0000-0000-000000000301"), title: "Survivor")
        let survivingLeaf = PaneLeafModel(
            id: uuid("00000000-0000-0000-0000-000000000003"),
            surfaces: [survivingSurface],
            activeSurfaceId: survivingSurface.id
        )
        var tree = PaneNodeModel.split(
            PaneSplitModel(
                id: uuid("00000000-0000-0000-0000-000000000004"),
                orientation: .horizontal,
                ratio: 0.5,
                first: .leaf(.empty()),
                second: .leaf(survivingLeaf)
            )
        )

        let isTreeEmpty = tree.compactEmptyLeaves()

        XCTAssertFalse(isTreeEmpty)
        XCTAssertEqual(tree, .leaf(survivingLeaf))
    }

    /// Verifies directional traversal picks neighboring panes in a nested grid.
    func testAdjacentPaneIdReturnsDirectionalNeighborInNestedGrid() {
        let topLeftLeaf = makeLeaf(
            paneId: uuid("00000000-0000-0000-0000-000000000011"),
            surfaceId: uuid("00000000-0000-0000-0000-000000000111")
        )
        let topRightLeaf = makeLeaf(
            paneId: uuid("00000000-0000-0000-0000-000000000012"),
            surfaceId: uuid("00000000-0000-0000-0000-000000000112")
        )
        let bottomLeftLeaf = makeLeaf(
            paneId: uuid("00000000-0000-0000-0000-000000000013"),
            surfaceId: uuid("00000000-0000-0000-0000-000000000113")
        )
        let bottomRightLeaf = makeLeaf(
            paneId: uuid("00000000-0000-0000-0000-000000000014"),
            surfaceId: uuid("00000000-0000-0000-0000-000000000114")
        )
        let tree = PaneNodeModel.split(
            PaneSplitModel(
                id: uuid("00000000-0000-0000-0000-000000000010"),
                orientation: .vertical,
                ratio: 0.5,
                first: .split(
                    PaneSplitModel(
                        id: uuid("00000000-0000-0000-0000-000000000020"),
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: topLeftLeaf,
                        second: topRightLeaf
                    )
                ),
                second: .split(
                    PaneSplitModel(
                        id: uuid("00000000-0000-0000-0000-000000000021"),
                        orientation: .horizontal,
                        ratio: 0.5,
                        first: bottomLeftLeaf,
                        second: bottomRightLeaf
                    )
                )
            )
        )

        XCTAssertEqual(
            tree.adjacentPaneId(from: uuid("00000000-0000-0000-0000-000000000011"), direction: .right),
            uuid("00000000-0000-0000-0000-000000000012")
        )
        XCTAssertEqual(
            tree.adjacentPaneId(from: uuid("00000000-0000-0000-0000-000000000011"), direction: .down),
            uuid("00000000-0000-0000-0000-000000000013")
        )
        XCTAssertEqual(
            tree.adjacentPaneId(from: uuid("00000000-0000-0000-0000-000000000014"), direction: .left),
            uuid("00000000-0000-0000-0000-000000000013")
        )
        XCTAssertEqual(
            tree.adjacentPaneId(from: uuid("00000000-0000-0000-0000-000000000014"), direction: .up),
            uuid("00000000-0000-0000-0000-000000000012")
        )
    }

    /// Builds a deterministic UUID for stable test fixtures.
    private func uuid(_ value: String) -> UUID {
        XCTAssertNotNil(UUID(uuidString: value))
        return UUID(uuidString: value)!
    }

    /// Builds a surface fixture with predictable defaults.
    private func makeSurface(id: UUID, title: String) -> SurfaceModel {
        SurfaceModel(
            id: id,
            title: title,
            agentType: .codex,
            sessionId: "session-\(title)",
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Builds a one-surface leaf node fixture.
    private func makeLeaf(paneId: UUID, surfaceId: UUID) -> PaneNodeModel {
        let surface = makeSurface(id: surfaceId, title: surfaceId.uuidString)
        return .leaf(
            PaneLeafModel(
                id: paneId,
                surfaces: [surface],
                activeSurfaceId: surface.id
            )
        )
    }
}
