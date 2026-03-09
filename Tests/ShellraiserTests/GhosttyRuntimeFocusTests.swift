import AppKit
import XCTest
@testable import Shellraiser

#if canImport(GhosttyKit)
/// Covers pending-focus restoration behavior in `GhosttyRuntime`.
@MainActor
final class GhosttyRuntimeFocusTests: XCTestCase {
    /// Verifies matching pending focus restores AppKit first responder and clears pending state.
    func testRestorePendingFocusIfNeededFocusesHostAndClearsPendingState() {
        let runtime = GhosttyRuntime()
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001341")!
        let window = makeWindow()
        let host = TestGhosttyFocusableHost()
        attach(host: host, to: window)

        runtime.pendingFocusedSurfaceIdForTesting = surfaceId
        runtime.restorePendingFocusIfNeeded(surfaceId: surfaceId, hostView: host)

        XCTAssertNil(runtime.pendingFocusedSurfaceIdForTesting)
        XCTAssertTrue(window.firstResponder === host)
    }

    /// Verifies mismatched restore requests leave pending state intact.
    func testRestorePendingFocusIfNeededIgnoresMismatchedSurfaceId() {
        let runtime = GhosttyRuntime()
        let pendingSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001342")!
        let otherSurfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001343")!
        let window = makeWindow()
        let host = TestGhosttyFocusableHost()
        let otherResponder = TestGhosttyFocusableHost()
        attach(host: host, to: window)
        attach(host: otherResponder, to: window)
        _ = window.makeFirstResponder(otherResponder)

        runtime.pendingFocusedSurfaceIdForTesting = pendingSurfaceId
        runtime.restorePendingFocusIfNeeded(surfaceId: otherSurfaceId, hostView: host)

        XCTAssertEqual(runtime.pendingFocusedSurfaceIdForTesting, pendingSurfaceId)
        XCTAssertTrue(window.firstResponder === otherResponder)
    }

    /// Creates a host window suitable for responder-chain tests.
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    /// Attaches a focusable test host to the window content view.
    private func attach(host: NSView, to window: NSWindow) {
        let container = window.contentView ?? NSView(frame: window.frame)
        if window.contentView == nil {
            window.contentView = container
        }
        host.frame = container.bounds
        container.addSubview(host)
    }
}

/// Minimal focusable host used to test runtime responder restoration.
@MainActor
private final class TestGhosttyFocusableHost: NSView, GhosttyFocusableHost {
    override var acceptsFirstResponder: Bool { true }

    /// Exposes the current AppKit window to the runtime under test.
    var hostWindow: NSWindow? { window }

    /// Supplies the responder target to make first responder.
    var firstResponderTarget: NSResponder { self }
}
#endif
