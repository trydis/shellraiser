import AppKit
import XCTest
@testable import Shellraiser

#if canImport(GhosttyKit)
/// Covers terminal-host synchronization used by `GhosttyTerminalView.updateNSView`.
@MainActor
final class GhosttyTerminalViewTests: XCTestCase {
    /// Verifies updating a host view re-applies focus state and pending-focus restoration.
    func testSyncHostViewUpdatesHostAndRequestsPendingFocusRestore() {
        let runtime = MockGhosttyTerminalRuntime()
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        GhosttyTerminalView.syncHostView(
            host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: true,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )

        XCTAssertEqual(host.updatedSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.surfaceId), [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.focused), [true])
        XCTAssertEqual(runtime.restorePendingFocusSurfaceIds, [surface.id])
        XCTAssertTrue(runtime.restoredHosts.first === host)
    }

    /// Verifies syncHostView forwards the onProgressReport closure to the host view.
    func testSyncHostViewForwardsProgressReportClosure() {
        let runtime = MockGhosttyTerminalRuntime()
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )
        var receivedReport: SurfaceProgressReport??
        let expectedReport = SurfaceProgressReport(state: .set, progress: 42)

        GhosttyTerminalView.syncHostView(
            host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: false,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { receivedReport = $0 }
        )

        host.progressReportHandler?(expectedReport)
        XCTAssertEqual(receivedReport, .some(expectedReport))
    }

    /// Verifies reparenting a shared host into a new wrapper keeps the host off the mount root.
    func testSyncContainerViewReparentsSharedHostWithoutDetachingCurrentMount() {
        let runtime = MockGhosttyTerminalRuntime()
        let firstContainer = GhosttyTerminalContainerView(frame: .zero)
        let secondContainer = GhosttyTerminalContainerView(frame: .zero)
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        GhosttyTerminalView.syncContainerView(
            firstContainer,
            host: host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: true,
            isWorkspaceSelected: true,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )
        GhosttyTerminalView.syncContainerView(
            secondContainer,
            host: host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: true,
            isWorkspaceSelected: true,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )

        XCTAssertTrue(host.superview === secondContainer)
        XCTAssertEqual(firstContainer.subviews.count, 0)
        XCTAssertEqual(secondContainer.subviews.count, 1)
        XCTAssertEqual(firstContainer.mountedSurfaceId, surface.id)
        XCTAssertEqual(secondContainer.mountedSurfaceId, surface.id)
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id, surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [])
        XCTAssertEqual(
            runtime.setSurfaceOcclusionCalls.map(\.occluded),
            [false, false],
            "selected workspace surfaces must be un-occluded on each sync"
        )
    }

    /// Verifies a wrapper swaps in the current cached host when the surface stays the same.
    func testSyncContainerViewReplacesMountedHostForSameSurfaceWithoutRemountingSurface() {
        let runtime = MockGhosttyTerminalRuntime()
        let container = GhosttyTerminalContainerView(frame: .zero)
        let firstHost = MockGhosttyTerminalHostView()
        let secondHost = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        GhosttyTerminalView.syncContainerView(
            container,
            host: firstHost,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: false,
            isWorkspaceSelected: true,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )
        GhosttyTerminalView.syncContainerView(
            container,
            host: secondHost,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: true,
            isWorkspaceSelected: true,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )

        XCTAssertTrue(firstHost.superview == nil)
        XCTAssertTrue(secondHost.superview === container)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertTrue(container.subviews.first === secondHost)
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [])
    }

    /// Verifies wrapper teardown decrements mount tracking for the mounted surface once.
    func testDismantleContainerViewDetachesMountedSurface() {
        let runtime = MockGhosttyTerminalRuntime()
        let container = GhosttyTerminalContainerView(frame: .zero)
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        GhosttyTerminalView.syncContainerView(
            container,
            host: host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: false,
            isWorkspaceSelected: false,
            onActivate: {},
            onIdleNotification: {},
            onInput: { _ in },
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in },
            onProgressReport: { _ in }
        )
        GhosttyTerminalView.dismantleContainerView(container, runtime: runtime)

        XCTAssertNil(container.mountedSurfaceId)
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [surface.id])
        XCTAssertEqual(
            runtime.setSurfaceOcclusionCalls.map(\.occluded),
            [true, true],
            "non-selected workspace surface must be occluded on sync and again on dismantle"
        )
    }

    /// Verifies that dismantling one of two active mounts for the same surface does NOT occlude it,
    /// because the second mount still shows the surface visibly.
    func testDismantleContainerViewDoesNotOccludeSurfaceWhenAnotherMountRemains() {
        let runtime = MockGhosttyTerminalRuntime()
        let firstContainer = GhosttyTerminalContainerView(frame: .zero)
        let secondContainer = GhosttyTerminalContainerView(frame: .zero)
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        let sync: (GhosttyTerminalContainerView) -> Void = { container in
            GhosttyTerminalView.syncContainerView(
                container,
                host: host,
                runtime: runtime,
                surface: surface,
                config: config,
                isFocused: false,
                isWorkspaceSelected: true,
                onActivate: {},
                onIdleNotification: {},
                onInput: { _ in },
                onTitleChange: { _ in },
                onWorkingDirectoryChange: { _ in },
                onChildExited: {},
                onPaneNavigationRequest: { _ in },
                onProgressReport: { _ in }
            )
        }

        // Mount surface in two containers (simulates reparent in progress).
        sync(firstContainer)
        sync(secondContainer)

        // Both attaches recorded; no detaches yet.
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id, surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [])

        // Dismantle one mount — second mount still active.
        GhosttyTerminalView.dismantleContainerView(firstContainer, runtime: runtime)

        XCTAssertNil(firstContainer.mountedSurfaceId)
        XCTAssertEqual(runtime.detachHostSurfaceIds, [surface.id])
        XCTAssertFalse(
            runtime.setSurfaceOcclusionCalls.contains(where: { $0.surfaceId == surface.id && $0.occluded }),
            "surface must NOT be occluded while a second mount still shows it"
        )
    }

    /// Verifies occlusion is re-applied reactively when workspace selection changes
    /// without the mounted surface changing.
    func testSyncContainerViewReappliesOcclusionOnWorkspaceSelectionChange() {
        let runtime = MockGhosttyTerminalRuntime()
        let container = GhosttyTerminalContainerView(frame: .zero)
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )

        let sync: (Bool) -> Void = { isSelected in
            GhosttyTerminalView.syncContainerView(
                container,
                host: host,
                runtime: runtime,
                surface: surface,
                config: config,
                isFocused: false,
                isWorkspaceSelected: isSelected,
                onActivate: {},
                onIdleNotification: {},
                onInput: { _ in },
                onTitleChange: { _ in },
                onWorkingDirectoryChange: { _ in },
                onChildExited: {},
                onPaneNavigationRequest: { _ in },
                onProgressReport: { _ in }
            )
        }

        sync(true)   // workspace selected → visible
        sync(false)  // workspace deselected → occlude
        sync(true)   // workspace reselected → visible again

        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id], "attach fires only on first mount")
        XCTAssertEqual(
            runtime.setSurfaceOcclusionCalls.map(\.occluded),
            [false, true, false],
            "occlusion must track workspace selection on every sync"
        )
    }
}

/// Minimal terminal host double used to exercise `syncHostView`.
@MainActor
private final class MockGhosttyTerminalHostView: NSView, GhosttyTerminalHostView {
    private(set) var updatedSurfaceIds: [UUID] = []
    private(set) var workingDirectoryChangeHandler: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    /// Exposes the current AppKit window to the runtime-facing host contract.
    var hostWindow: NSWindow? { window }

    /// Supplies the responder target to make first responder.
    var firstResponderTarget: NSResponder { self }

    private(set) var progressReportHandler: ((SurfaceProgressReport?) -> Void)?

    /// Records host updates dispatched through the terminal view helper.
    func update(
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onInput: @escaping (SurfaceInputEvent) -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void,
        onProgressReport: @escaping (SurfaceProgressReport?) -> Void
    ) {
        _ = terminalConfig
        _ = onActivate
        _ = onIdleNotification
        _ = onInput
        _ = onTitleChange
        workingDirectoryChangeHandler = onWorkingDirectoryChange
        _ = onChildExited
        _ = onPaneNavigationRequest
        progressReportHandler = onProgressReport
        updatedSurfaceIds.append(surfaceModel.id)
    }
}

/// Runtime double that records focus synchronization calls from `GhosttyTerminalView`.
@MainActor
private final class MockGhosttyTerminalRuntime: GhosttyTerminalRuntimeControlling {
    private(set) var attachHostSurfaceIds: [UUID] = []
    private(set) var detachHostSurfaceIds: [UUID] = []
    private(set) var setSurfaceFocusCalls: [(surfaceId: UUID, focused: Bool)] = []
    private(set) var setSurfaceOcclusionCalls: [(surfaceId: UUID, occluded: Bool)] = []
    private(set) var restorePendingFocusSurfaceIds: [UUID] = []
    private(set) var restoredHosts: [AnyObject] = []

    /// Records wrapper-view mount registrations for a surface.
    func attachHost(surfaceId: UUID) {
        attachHostSurfaceIds.append(surfaceId)
    }

    /// Records wrapper-view unmount registrations for a surface.
    func detachHost(surfaceId: UUID) {
        detachHostSurfaceIds.append(surfaceId)
    }

    /// Returns the simulated remaining mount count for a surface (attaches minus detaches).
    func mountedHostCount(surfaceId: UUID) -> Int {
        let attached = attachHostSurfaceIds.filter { $0 == surfaceId }.count
        let detached = detachHostSurfaceIds.filter { $0 == surfaceId }.count
        return max(0, attached - detached)
    }

    /// Records direct focus-state updates for a surface.
    func setSurfaceFocus(surfaceId: UUID, focused: Bool) {
        setSurfaceFocusCalls.append((surfaceId: surfaceId, focused: focused))
    }

    /// Records occlusion state changes for a surface.
    func setSurfaceOcclusion(surfaceId: UUID, occluded: Bool) {
        setSurfaceOcclusionCalls.append((surfaceId: surfaceId, occluded: occluded))
    }

    /// Records pending-focus restore attempts for a host view.
    func restorePendingFocusIfNeeded(surfaceId: UUID, hostView: any GhosttyFocusableHost) {
        restorePendingFocusSurfaceIds.append(surfaceId)
        restoredHosts.append(hostView)
    }
}
#endif
