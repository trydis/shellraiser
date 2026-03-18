import AppKit
import Foundation
import XCTest
@testable import Shellraiser

/// Shared fixtures and persistence helpers for workspace service tests.
class WorkspaceTestCase: XCTestCase {
    /// Creates a persistence instance rooted in a unique test directory.
    func makePersistence(testName: String = #function) -> WorkspacePersistence {
        makePersistenceContext(testName: testName).persistence
    }

    /// Creates a persistence instance together with its isolated test directory.
    func makePersistenceContext(testName: String = #function) -> (persistence: WorkspacePersistence, directory: URL) {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let subdirectory = "ShellraiserTests-\(sanitizedTestName)-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(subdirectory, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        return (WorkspacePersistence(directoryURL: directory, logsErrors: false), directory)
    }

    /// Creates a deterministic surface fixture with overridable state.
    func makeSurface(
        id: UUID = UUID(),
        title: String = "~",
        agentType: AgentType = .codex,
        sessionId: String = "",
        transcriptPath: String = "",
        shouldResumeSession: Bool = false,
        isIdle: Bool = false,
        hasUnreadIdleNotification: Bool = false,
        hasPendingCompletion: Bool = false,
        pendingCompletionSequence: Int? = nil,
        lastCompletionAt: Date? = nil,
        lastActivity: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SurfaceModel {
        SurfaceModel(
            id: id,
            title: title,
            agentType: agentType,
            sessionId: sessionId,
            transcriptPath: transcriptPath,
            shouldResumeSession: shouldResumeSession,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: isIdle,
            hasUnreadIdleNotification: hasUnreadIdleNotification,
            hasPendingCompletion: hasPendingCompletion,
            pendingCompletionSequence: pendingCompletionSequence,
            lastCompletionAt: lastCompletionAt,
            lastActivity: lastActivity
        )
    }

    /// Creates a leaf pane fixture with a selectable active surface.
    func makeLeaf(
        paneId: UUID = UUID(),
        surfaces: [SurfaceModel],
        activeSurfaceId: UUID? = nil
    ) -> PaneNodeModel {
        .leaf(
            PaneLeafModel(
                id: paneId,
                surfaces: surfaces,
                activeSurfaceId: activeSurfaceId ?? surfaces.first?.id
            )
        )
    }

    /// Creates a workspace fixture with a supplied root pane.
    func makeWorkspace(
        id: UUID = UUID(),
        name: String = "Workspace",
        rootPane: PaneNodeModel,
        focusedSurfaceId: UUID? = nil,
        zoomedPaneId: UUID? = nil,
        rootWorkingDirectory: String? = nil
    ) -> WorkspaceModel {
        WorkspaceModel(
            id: id,
            name: name,
            rootPane: rootPane,
            focusedSurfaceId: focusedSurfaceId,
            zoomedPaneId: zoomedPaneId,
            rootWorkingDirectory: rootWorkingDirectory ?? workspaceRootWorkingDirectory(from: rootPane)
        )
    }

    /// Returns the first available working directory in a pane tree for stable workspace-root defaults.
    private func workspaceRootWorkingDirectory(from rootPane: PaneNodeModel) -> String {
        switch rootPane {
        case .leaf(let leaf):
            return leaf.surfaces.first?.terminalConfig.workingDirectory ?? NSHomeDirectory()
        case .split(let split):
            let firstPath = workspaceRootWorkingDirectory(from: split.first)
            if firstPath != NSHomeDirectory() {
                return firstPath
            }
            return workspaceRootWorkingDirectory(from: split.second)
        }
    }

    /// Returns the first surface stored in a leaf pane.
    func surface(in rootPane: PaneNodeModel, paneId: UUID) -> SurfaceModel? {
        guard case .leaf(let leaf) = rootPane.paneNode(id: paneId) else { return nil }
        return leaf.surfaces.first
    }

    /// Returns a specific surface by identifier anywhere in the pane tree.
    func surface(in rootPane: PaneNodeModel, surfaceId: UUID) -> SurfaceModel? {
        switch rootPane {
        case .leaf(let leaf):
            return leaf.surfaces.first(where: { $0.id == surfaceId })
        case .split(let split):
            return surface(in: split.first, surfaceId: surfaceId) ?? surface(in: split.second, surfaceId: surfaceId)
        }
    }

    /// Creates a workspace manager with controllable test doubles.
    @MainActor
    func makeWorkspaceManager(
        persistence: (any WorkspacePersisting)? = nil,
        workspaceCatalog: WorkspaceCatalogManager = WorkspaceCatalogManager(),
        surfaceManager: WorkspaceSurfaceManager = WorkspaceSurfaceManager(),
        runtimeBridge: MockAgentRuntimeBridge? = nil,
        notifications: MockAgentCompletionNotificationManager? = nil,
        eventMonitor: MockAgentActivityEventMonitor? = nil,
        confirmWorkspaceDeletion: @escaping WorkspaceManager.WorkspaceDeletionConfirmer = { _ in true },
        gitStateResolver: @escaping WorkspaceManager.GitStateResolver = {
            GitBranchResolver().resolveGitState(forWorkingDirectory: $0)
        }
    ) -> WorkspaceManager {
        return WorkspaceManager(
            persistence: persistence ?? InMemoryWorkspacePersistence(),
            workspaceCatalog: workspaceCatalog,
            surfaceManager: surfaceManager,
            runtimeBridge: runtimeBridge ?? MockAgentRuntimeBridge(),
            completionNotifications: notifications ?? MockAgentCompletionNotificationManager(),
            activityEventMonitor: eventMonitor ?? MockAgentActivityEventMonitor(),
            registersLocalShortcutMonitor: false,
            confirmWorkspaceDeletion: confirmWorkspaceDeletion,
            gitStateResolver: gitStateResolver
        )
    }
}

/// In-memory persistence double for manager tests that should avoid filesystem I/O.
final class InMemoryWorkspacePersistence: WorkspacePersisting {
    private var storedWorkspaces: [WorkspaceModel]?

    /// Returns the last workspaces snapshot written into the test double.
    func load() -> [WorkspaceModel]? {
        storedWorkspaces
    }

    /// Replaces the stored workspace snapshot in memory.
    func save(_ workspaces: [WorkspaceModel]) {
        storedWorkspaces = workspaces
    }

    /// In-memory persistence completes writes eagerly, so flushing is a no-op.
    func flush() {}
}

/// Minimal runtime-bridge test double for workspace-manager orchestration tests.
@MainActor
final class MockAgentRuntimeBridge: AgentRuntimeSupporting {
    private(set) var prepareRuntimeSupportCallCount = 0
    let eventLogURL: URL

    /// Creates a mock runtime bridge with a disposable event log URL.
    init(eventLogURL: URL = URL(fileURLWithPath: "/tmp/shellraiser-tests-event-log")) {
        self.eventLogURL = eventLogURL
    }

    /// Records runtime preparation calls from manager initialization.
    func prepareRuntimeSupport() {
        prepareRuntimeSupportCallCount += 1
    }
}

/// Notification-manager test double that records scheduling and removal.
final class MockAgentCompletionNotificationManager: AgentCompletionNotificationManaging {
    var onActivateSurface: ((UUID) -> Void)?
    private(set) var scheduledNotifications: [(target: PendingCompletionTarget, workspaceName: String)] = []
    private(set) var removedSurfaceIds: [UUID] = []

    /// Records notification scheduling requests.
    func scheduleNotification(target: PendingCompletionTarget, workspaceName: String) {
        scheduledNotifications.append((target: target, workspaceName: workspaceName))
    }

    /// Records notification-removal requests.
    func removeNotifications(for surfaceId: UUID) {
        removedSurfaceIds.append(surfaceId)
    }
}

/// Activity-event monitor test double that allows tests to trigger callbacks manually.
final class MockAgentActivityEventMonitor: AgentActivityEventMonitoring {
    var onEvent: ((AgentActivityEvent) -> Void)?

    /// Emits a synthetic activity event into the manager under test.
    func emit(_ event: AgentActivityEvent) {
        onEvent?(event)
    }
}
