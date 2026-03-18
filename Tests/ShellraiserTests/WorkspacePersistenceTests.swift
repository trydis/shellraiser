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

    /// Verifies persisted JSON uses a compact encoding without pretty-printed whitespace.
    func testSaveUsesCompactJSONEncoding() throws {
        let context = makePersistenceContext()
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001041")!,
            name: "Compact",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001042")!,
                surfaces: [
                    makeSurface(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001043")!,
                        title: "Compact Surface"
                    )
                ]
            )
        )

        context.persistence.save([workspace])

        let workspaceFile = context.directory.appendingPathComponent("workspaces.json")
        let encodedJSON = try XCTUnwrap(String(data: Data(contentsOf: workspaceFile), encoding: .utf8))

        XCTAssertFalse(encodedJSON.contains("\n"))
        XCTAssertFalse(encodedJSON.contains("  "))
        XCTAssertTrue(encodedJSON.hasPrefix("[{"))
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

    /// Verifies safe single-component overrides are still honored for isolated persistence roots.
    func testPersistenceUsesValidatedOverrideSubdirectory() throws {
        let subdirectory = "ShellraiserDev-Validated_01"
        setenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey, subdirectory, 1)
        setenv(WorkspacePersistence.suppressErrorLoggingEnvironmentKey, "1", 1)
        addTeardownBlock {
            unsetenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey)
            unsetenv(WorkspacePersistence.suppressErrorLoggingEnvironmentKey)

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(
                at: appSupport.appendingPathComponent(subdirectory, isDirectory: true)
            )
        }

        let persistence = WorkspacePersistence()
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001021")!,
            name: "Validated Override",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001022")!,
                surfaces: [
                    makeSurface(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001023")!,
                        title: "Validated"
                    )
                ]
            )
        )
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let overrideFile = appSupport
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent("workspaces.json")

        persistence.save([workspace])

        XCTAssertTrue(FileManager.default.fileExists(atPath: overrideFile.path))
        XCTAssertEqual(persistence.load(), [workspace])
    }

    /// Verifies invalid overrides cannot escape the default Application Support location.
    func testPersistenceRejectsUnsafeOverrideSubdirectory() throws {
        let invalidOverride = "../ShellraiserEscape"
        let defaultDirectory = "Shellraiser"
        setenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey, invalidOverride, 1)
        setenv(WorkspacePersistence.suppressErrorLoggingEnvironmentKey, "1", 1)
        addTeardownBlock {
            unsetenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey)
            unsetenv(WorkspacePersistence.suppressErrorLoggingEnvironmentKey)

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(
                at: appSupport.appendingPathComponent(defaultDirectory, isDirectory: true)
            )
        }

        let persistence = WorkspacePersistence()
        let workspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001031")!,
            name: "Unsafe Override Fallback",
            rootPane: makeLeaf(
                paneId: UUID(uuidString: "00000000-0000-0000-0000-000000001032")!,
                surfaces: [
                    makeSurface(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001033")!,
                        title: "Fallback"
                    )
                ]
            )
        )
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultFile = appSupport
            .appendingPathComponent(defaultDirectory, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let escapedFile = appSupport
            .appendingPathComponent(invalidOverride, isDirectory: true)
            .appendingPathComponent("workspaces.json")

        persistence.save([workspace])

        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: escapedFile.path))
        XCTAssertEqual(persistence.load(), [workspace])
    }
}
