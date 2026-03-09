import XCTest
@testable import Shellraiser

/// Thread-safe resolver double that can pause selected directory lookups.
private final class ControlledGitStateResolver: @unchecked Sendable {
    private let lock = NSLock()
    private let resolvedStates: [String: ResolvedGitState]
    private var startedDirectories: Set<String> = []
    private var blockedDirectorySemaphores: [String: DispatchSemaphore] = [:]

    /// Creates a resolver with predefined states and optionally blocked directories.
    init(
        resolvedStates: [String: ResolvedGitState],
        blockedDirectories: Set<String> = []
    ) {
        self.resolvedStates = resolvedStates
        self.blockedDirectorySemaphores = Dictionary(
            uniqueKeysWithValues: blockedDirectories.map { ($0, DispatchSemaphore(value: 0)) }
        )
    }

    /// Resolves the injected state for a working directory, optionally blocking until released.
    func resolve(workingDirectory: String) -> ResolvedGitState? {
        let semaphore: DispatchSemaphore? = withLock {
            startedDirectories.insert(workingDirectory)
            return blockedDirectorySemaphores[workingDirectory]
        }

        semaphore?.wait()
        return resolvedStates[workingDirectory]
    }

    /// Returns whether the resolver has started handling the supplied directory.
    func hasStarted(workingDirectory: String) -> Bool {
        withLock {
            startedDirectories.contains(workingDirectory)
        }
    }

    /// Releases a previously blocked directory lookup.
    func unblock(workingDirectory: String) {
        withLock {
            blockedDirectorySemaphores[workingDirectory]
        }?.signal()
    }

    /// Performs a thread-safe read or mutation against the resolver state.
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

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
    func testSetSurfaceWorkingDirectoryNormalizesPathBeforeRefreshingGitState() async {
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

        await refreshTask?.value

        XCTAssertEqual(manager.gitStatesBySurfaceId[surface.id], expectedState)
    }

    /// Verifies a slower stale refresh cannot overwrite the latest working-directory state.
    func testSetSurfaceWorkingDirectoryIgnoresStaleGitRefreshResults() async {
        let firstWorkingDirectory = "/tmp/repo-a"
        let secondWorkingDirectory = "/tmp/repo-b"
        let firstState = ResolvedGitState(branchName: "feature/slow", isLinkedWorktree: false)
        let secondState = ResolvedGitState(branchName: "main", isLinkedWorktree: false)
        let resolver = ControlledGitStateResolver(
            resolvedStates: [
                firstWorkingDirectory: firstState,
                secondWorkingDirectory: secondState
            ],
            blockedDirectories: [firstWorkingDirectory]
        )
        let manager = makeWorkspaceManager(
            gitStateResolver: { workingDirectory in
                resolver.resolve(workingDirectory: workingDirectory)
            }
        )
        let surface = makeSurface(id: UUID(uuidString: "00000000-0000-0000-0000-000000001331")!)
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001332")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001333")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                rootPane: makeLeaf(paneId: paneId, surfaces: [surface]),
                focusedSurfaceId: surface.id
            )
        ]

        let firstRefreshTask = manager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workingDirectory: firstWorkingDirectory
        )
        let firstResolverStarted = await waitForResolverStart(
            resolver,
            workingDirectory: firstWorkingDirectory
        )
        XCTAssertTrue(firstResolverStarted)

        let secondRefreshTask = manager.setSurfaceWorkingDirectory(
            workspaceId: workspaceId,
            surfaceId: surface.id,
            workingDirectory: secondWorkingDirectory
        )
        await secondRefreshTask?.value

        XCTAssertEqual(
            manager.surface(in: manager.workspaces[0].rootPane, surfaceId: surface.id)?.terminalConfig.workingDirectory,
            secondWorkingDirectory
        )
        XCTAssertEqual(manager.gitStatesBySurfaceId[surface.id], secondState)

        resolver.unblock(workingDirectory: firstWorkingDirectory)
        await firstRefreshTask?.value

        XCTAssertEqual(manager.gitStatesBySurfaceId[surface.id], secondState)
    }

    /// Waits until the injected resolver has started processing a working directory.
    private func waitForResolverStart(
        _ resolver: ControlledGitStateResolver,
        workingDirectory: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .nanoseconds(Int(timeoutNanoseconds))

        while clock.now < deadline {
            if resolver.hasStarted(workingDirectory: workingDirectory) {
                return true
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        return resolver.hasStarted(workingDirectory: workingDirectory)
    }
}
