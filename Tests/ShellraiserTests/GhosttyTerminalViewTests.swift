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
            onUserInput: {},
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )

        XCTAssertEqual(host.updatedSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.surfaceId), [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.focused), [true])
        XCTAssertEqual(runtime.restorePendingFocusSurfaceIds, [surface.id])
        XCTAssertTrue(runtime.restoredHosts.first === host)
    }

    /// Verifies remounting the same shared host into a new wrapper view reparents the host cleanly.
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
            onActivate: {},
            onIdleNotification: {},
            onUserInput: {},
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )
        GhosttyTerminalView.syncContainerView(
            secondContainer,
            host: host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: true,
            onActivate: {},
            onIdleNotification: {},
            onUserInput: {},
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )

        XCTAssertTrue(host.superview === secondContainer)
        XCTAssertEqual(firstContainer.subviews.count, 0)
        XCTAssertEqual(secondContainer.subviews.count, 1)
        XCTAssertEqual(firstContainer.mountedSurfaceId, surface.id)
        XCTAssertEqual(secondContainer.mountedSurfaceId, surface.id)
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id, surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [])
    }

    /// Verifies working-directory change callbacks are forwarded through host synchronization.
    func testSyncHostViewForwardsWorkingDirectoryChangeHandler() {
        let runtime = MockGhosttyTerminalRuntime()
        let host = MockGhosttyTerminalHostView()
        let surface = SurfaceModel.makeDefault()
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp",
            shell: "/bin/zsh",
            environment: [:]
        )
        var reportedWorkingDirectories: [String] = []

        GhosttyTerminalView.syncHostView(
            host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: false,
            onActivate: {},
            onIdleNotification: {},
            onUserInput: {},
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { reportedWorkingDirectories.append($0) },
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )

        host.workingDirectoryChangeHandler?("new/path")

        XCTAssertEqual(reportedWorkingDirectories, ["new/path"])
    }

    /// Verifies wrapper teardown decrements mount tracking for the surface once.
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
            onActivate: {},
            onIdleNotification: {},
            onUserInput: {},
            onTitleChange: { _ in },
            onWorkingDirectoryChange: { _ in },
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )
        GhosttyTerminalView.dismantleContainerView(container, runtime: runtime)

        XCTAssertNil(container.mountedSurfaceId)
        XCTAssertEqual(runtime.attachHostSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.detachHostSurfaceIds, [surface.id])
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

    /// Records host updates dispatched through the terminal view helper.
    func update(
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onUserInput: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) {
        _ = terminalConfig
        _ = onActivate
        _ = onIdleNotification
        _ = onUserInput
        _ = onTitleChange
        workingDirectoryChangeHandler = onWorkingDirectoryChange
        _ = onChildExited
        _ = onPaneNavigationRequest
        updatedSurfaceIds.append(surfaceModel.id)
    }
}

/// Runtime double that records focus synchronization calls from `GhosttyTerminalView`.
@MainActor
private final class MockGhosttyTerminalRuntime: GhosttyTerminalRuntimeControlling {
    private(set) var attachHostSurfaceIds: [UUID] = []
    private(set) var detachHostSurfaceIds: [UUID] = []
    private(set) var setSurfaceFocusCalls: [(surfaceId: UUID, focused: Bool)] = []
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

    /// Records direct focus-state updates for a surface.
    func setSurfaceFocus(surfaceId: UUID, focused: Bool) {
        setSurfaceFocusCalls.append((surfaceId: surfaceId, focused: focused))
    }

    /// Records pending-focus restore attempts for a host view.
    func restorePendingFocusIfNeeded(surfaceId: UUID, hostView: any GhosttyFocusableHost) {
        restorePendingFocusSurfaceIds.append(surfaceId)
        restoredHosts.append(hostView)
    }
}
#endif
