import XCTest
@testable import Shellraiser

/// Covers filesystem-backed workspace persistence behavior.
final class WorkspacePersistenceTests: WorkspaceTestCase {
    /// Verifies loading with no persisted file returns nil instead of an empty placeholder array.
    func testLoadReturnsNilWhenPersistenceFileDoesNotExist() {
        let persistence = makePersistence()

        XCTAssertNil(persistence.load())
    }

    /// Verifies saving and loading preserve the workspace graph and metadata.
    func testSaveAndLoadRoundTripWorkspaces() {
        let persistence = makePersistence()
        let firstSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            title: "First",
            agentType: .codex,
            sessionId: "session-1",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 12,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_002_000),
            lastActivity: Date(timeIntervalSince1970: 1_700_002_100)
        )
        let secondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001002")!,
            title: "Second"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001003")!
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001004")!,
            name: "Round Trip",
            rootPane: .split(
                PaneSplitModel(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000001005")!,
                    orientation: .horizontal,
                    ratio: 0.4,
                    first: makeLeaf(paneId: paneId, surfaces: [firstSurface], activeSurfaceId: firstSurface.id),
                    second: makeLeaf(
                        paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001006")!,
                        surfaces: [secondSurface],
                        activeSurfaceId: secondSurface.id
                    )
                )
            ),
            focusedSurfaceId: firstSurface.id,
            zoomedPaneId: paneId
        )

        persistence.save([workspace])

        XCTAssertEqual(persistence.load(), [workspace])
    }

    /// Verifies corrupt persistence payloads fail closed by returning nil.
    func testLoadReturnsNilForCorruptPersistenceFile() throws {
        let context = makePersistenceContext()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: context.directory, withIntermediateDirectories: true)
        let workspaceFile = context.directory.appendingPathComponent("workspaces.json")
        try Data("not valid json".utf8).write(to: workspaceFile, options: .atomic)

        XCTAssertNil(context.persistence.load())
    }

    /// Verifies environment-subdirectory overrides isolate independent persistence instances.
    func testPersistenceOverrideSubdirectoriesDoNotLeakAcrossInstances() {
        let firstContext = makePersistenceContext()
        let secondContext = makePersistenceContext()
        let firstSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001011")!,
            title: "First",
            lastActivity: Date(timeIntervalSince1970: 1_700_003_000)
        )
        let secondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001012")!,
            title: "Second",
            lastActivity: Date(timeIntervalSince1970: 1_700_003_100)
        )
        let firstWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001013")!,
            name: "First",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001014")!,
                surfaces: [firstSurface],
                activeSurfaceId: firstSurface.id
            ),
            focusedSurfaceId: firstSurface.id
        )
        let secondWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001015")!,
            name: "Second",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001016")!,
                surfaces: [secondSurface],
                activeSurfaceId: secondSurface.id
            ),
            focusedSurfaceId: secondSurface.id
        )

        firstContext.persistence.save([firstWorkspace])
        secondContext.persistence.save([secondWorkspace])

        XCTAssertEqual(firstContext.persistence.load(), [firstWorkspace])
        XCTAssertEqual(secondContext.persistence.load(), [secondWorkspace])
    }
}
