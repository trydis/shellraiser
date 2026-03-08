import Foundation
import XCTest
@testable import Shellraiser

/// Shared fixtures and persistence helpers for workspace service tests.
class WorkspaceTestCase: XCTestCase {
    /// Creates a persistence instance rooted in a unique Application Support subdirectory.
    func makePersistence(testName: String = #function) -> WorkspacePersistence {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let subdirectory = "ShellraiserTests-\(sanitizedTestName)-\(UUID().uuidString)"

        setenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey, subdirectory, 1)
        addTeardownBlock {
            unsetenv(WorkspacePersistence.appSupportSubdirectoryEnvironmentKey)

            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let testDirectory = appSupport.appendingPathComponent(subdirectory, isDirectory: true)
            try? fileManager.removeItem(at: testDirectory)
        }

        return WorkspacePersistence()
    }

    /// Creates a deterministic surface fixture with overridable state.
    func makeSurface(
        id: UUID = UUID(),
        title: String = "~",
        agentType: AgentType = .codex,
        sessionId: String = "",
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
        zoomedPaneId: UUID? = nil
    ) -> WorkspaceModel {
        WorkspaceModel(
            id: id,
            name: name,
            rootPane: rootPane,
            focusedSurfaceId: focusedSurfaceId,
            zoomedPaneId: zoomedPaneId
        )
    }
}
