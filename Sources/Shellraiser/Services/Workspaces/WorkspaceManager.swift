import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Searchable command palette entry describing one invokable app action.
struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let category: String
    let systemImage: String
    let shortcut: String?
    let isEnabled: Bool
    let keywords: [String]
    let action: () -> Void

    /// Combined searchable text used by palette filtering.
    var searchText: String {
        ([title, category] + keywords + (shortcut.map { [$0] } ?? []))
            .joined(separator: " ")
    }
}

/// Pending workspace deletion confirmation request.
struct WorkspaceDeletionRequest: Identifiable {
    let workspaceId: UUID
    let workspaceName: String
    let activeProcessCount: Int

    /// Stable identity used by SwiftUI alert presentation.
    var id: UUID { workspaceId }
}

/// Pending workspace rename request presented through the shared naming sheet.
struct WorkspaceRenameRequest: Identifiable {
    let workspaceId: UUID
    let currentName: String

    /// Stable identity used by SwiftUI sheet presentation.
    var id: UUID { workspaceId }
}

/// Central app-state manager for window, workspace, pane, and surface operations.
@MainActor
final class WorkspaceManager: ObservableObject {
    /// Callable resolver used to derive Git state from a working directory.
    typealias GitStateResolver = @Sendable (String) -> ResolvedGitState?

    /// App-owned commands that operate on the focused pane and its active tab.
    enum FocusedPaneCommand {
        case newSurface
        case split(SplitOrientation)
        case closeActiveItem
        case focus(PaneNodeModel.PaneFocusDirection)
        case nextSurface
        case previousSurface
        case toggleZoom
    }

    /// Resolved pane command target used by menu actions and local shortcuts.
    struct PaneCommandContext {
        let workspaceId: UUID
        let workspace: WorkspaceModel
        let paneId: UUID
        let surfaceId: UUID?
    }

    @Published var workspaces: [WorkspaceModel] = []
    @Published var window: WindowModel = .initial()
    @Published var isCommandPalettePresented = false
    @Published var pendingWorkspaceDeletion: WorkspaceDeletionRequest?
    @Published var pendingWorkspaceRename: WorkspaceRenameRequest?
    @Published var gitStatesBySurfaceId: [UUID: ResolvedGitState] = [:]
    @Published var busySurfaceIds: Set<UUID> = []
    var liveCodexSessionSurfaceIds: Set<UUID> = []

    let persistence: any WorkspacePersisting
    let workspaceCatalog: WorkspaceCatalogManager
    let surfaceManager: WorkspaceSurfaceManager
    let runtimeBridge: any AgentRuntimeSupporting
    let completionNotifications: any AgentCompletionNotificationManaging
    let activityEventMonitor: any AgentActivityEventMonitoring
    let gitStateResolver: GitStateResolver
    var localShortcutMonitor: Any?
    var nextPendingCompletionSequence = 1
    var recentlyHandledSurfaceFadeStarts: [UUID: Date] = [:]
    var recentlyHandledSurfaceExpirations: [UUID: Date] = [:]
    var hasLoadedPersistedWorkspaces = false
    var isTerminating = false
    var willTerminateObserver: NSObjectProtocol?

    /// Creates a manager with explicit dependencies for testability.
    init(
        persistence: any WorkspacePersisting = WorkspacePersistence(),
        workspaceCatalog: WorkspaceCatalogManager = WorkspaceCatalogManager(),
        surfaceManager: WorkspaceSurfaceManager = WorkspaceSurfaceManager(),
        runtimeBridge: (any AgentRuntimeSupporting)? = nil,
        completionNotifications: any AgentCompletionNotificationManaging = AgentCompletionNotificationManager(),
        activityEventMonitor: (any AgentActivityEventMonitoring)? = nil,
        registersLocalShortcutMonitor: Bool = true,
        gitStateResolver: @escaping GitStateResolver = {
            GitBranchResolver().resolveGitState(forWorkingDirectory: $0)
        }
    ) {
        let resolvedRuntimeBridge = runtimeBridge ?? AgentRuntimeBridge.shared
        let resolvedActivityEventMonitor = activityEventMonitor
            ?? AgentCompletionEventMonitor(logURL: resolvedRuntimeBridge.eventLogURL)

        self.persistence = persistence
        self.workspaceCatalog = workspaceCatalog
        self.surfaceManager = surfaceManager
        self.runtimeBridge = resolvedRuntimeBridge
        self.completionNotifications = completionNotifications
        resolvedRuntimeBridge.prepareRuntimeSupport()
        self.activityEventMonitor = resolvedActivityEventMonitor
        self.gitStateResolver = gitStateResolver

        completionNotifications.onActivateSurface = { [weak self] surfaceId in
            Task { @MainActor in
                self?.focusCompletionSurface(surfaceId)
            }
        }
        resolvedActivityEventMonitor.onEvent = { [weak self] event in
            self?.handleAgentActivityEvent(event)
        }
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForTermination()
            }
        }

        if registersLocalShortcutMonitor {
            registerLocalShortcutMonitor()
        }
    }

    deinit {
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
        }
        if let willTerminateObserver {
            NotificationCenter.default.removeObserver(willTerminateObserver)
        }
    }
}
