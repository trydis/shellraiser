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
            onChildExited: {},
            onPaneNavigationRequest: { _ in }
        )

        XCTAssertEqual(host.updatedSurfaceIds, [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.surfaceId), [surface.id])
        XCTAssertEqual(runtime.setSurfaceFocusCalls.map(\.focused), [true])
        XCTAssertEqual(runtime.restorePendingFocusSurfaceIds, [surface.id])
        XCTAssertTrue(runtime.restoredHosts.first === host)
    }
}

/// Minimal terminal host double used to exercise `syncHostView`.
@MainActor
private final class MockGhosttyTerminalHostView: NSView, GhosttyTerminalHostView {
    private(set) var updatedSurfaceIds: [UUID] = []

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
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) {
        _ = terminalConfig
        _ = onActivate
        _ = onIdleNotification
        _ = onUserInput
        _ = onTitleChange
        _ = onChildExited
        _ = onPaneNavigationRequest
        updatedSurfaceIds.append(surfaceModel.id)
    }
}

/// Runtime double that records focus synchronization calls from `GhosttyTerminalView`.
@MainActor
private final class MockGhosttyTerminalRuntime: GhosttyTerminalRuntimeControlling {
    private(set) var setSurfaceFocusCalls: [(surfaceId: UUID, focused: Bool)] = []
    private(set) var restorePendingFocusSurfaceIds: [UUID] = []
    private(set) var restoredHosts: [AnyObject] = []

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
