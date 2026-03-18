import XCTest
@testable import Shellraiser

/// Covers debounced workspace persistence behavior and flush semantics.
@MainActor
final class CoalescingWorkspacePersistenceTests: WorkspaceTestCase {
    /// Verifies repeated saves inside the debounce window collapse to one backing write.
    func testSaveCoalescesRepeatedWritesAndPersistsLatestSnapshot() async {
        let backing = RecordingWorkspacePersistence()
        let persistence = CoalescingWorkspacePersistence(backing: backing, debounceInterval: 0.05)
        let firstWorkspace = WorkspaceModel.makeDefault(name: "First")
        let secondWorkspace = WorkspaceModel.makeDefault(name: "Second")

        persistence.save([firstWorkspace])
        persistence.save([secondWorkspace])

        XCTAssertTrue(backing.savedSnapshots.isEmpty)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(backing.savedSnapshots, [[secondWorkspace]])
        XCTAssertEqual(backing.flushCallCount, 1)
    }

    /// Verifies flushing bypasses the debounce delay and writes immediately.
    func testFlushPersistsPendingSnapshotImmediately() {
        let backing = RecordingWorkspacePersistence()
        let persistence = CoalescingWorkspacePersistence(backing: backing, debounceInterval: 60)
        let workspace = WorkspaceModel.makeDefault(name: "Flush")

        persistence.save([workspace])
        persistence.flush()

        XCTAssertEqual(backing.savedSnapshots, [[workspace]])
        XCTAssertEqual(backing.flushCallCount, 1)
    }

    /// Verifies pending snapshots are visible to immediate reads before disk flush.
    func testLoadReturnsPendingSnapshotBeforeFlush() {
        let backing = RecordingWorkspacePersistence()
        let persistence = CoalescingWorkspacePersistence(backing: backing, debounceInterval: 60)
        let workspace = WorkspaceModel.makeDefault(name: "Pending")

        persistence.save([workspace])

        XCTAssertEqual(persistence.load(), [workspace])
        XCTAssertTrue(backing.savedSnapshots.isEmpty)
    }

    /// Verifies loads fall back to the wrapped persistence when no save is pending.
    func testLoadFallsBackToBackingPersistenceWhenNoPendingSnapshot() {
        let workspace = WorkspaceModel.makeDefault(name: "Persisted")
        let backing = RecordingWorkspacePersistence(loadedWorkspaces: [workspace])
        let persistence = CoalescingWorkspacePersistence(backing: backing, debounceInterval: 60)

        XCTAssertEqual(persistence.load(), [workspace])
        XCTAssertEqual(backing.loadCallCount, 1)
    }
}

/// Recording persistence double used to assert debounced save behavior.
final class RecordingWorkspacePersistence: WorkspacePersisting {
    private(set) var loadCallCount = 0
    private(set) var flushCallCount = 0
    private(set) var savedSnapshots: [[WorkspaceModel]] = []
    private let loadedWorkspaces: [WorkspaceModel]?

    /// Creates a recording double with an optional preloaded snapshot.
    init(loadedWorkspaces: [WorkspaceModel]? = nil) {
        self.loadedWorkspaces = loadedWorkspaces
    }

    /// Returns the preloaded snapshot and tracks load access.
    func load() -> [WorkspaceModel]? {
        loadCallCount += 1
        return loadedWorkspaces
    }

    /// Records each persisted workspace snapshot.
    func save(_ workspaces: [WorkspaceModel]) {
        savedSnapshots.append(workspaces)
    }

    /// Records flush calls from the coalescing wrapper.
    func flush() {
        flushCallCount += 1
    }
}
