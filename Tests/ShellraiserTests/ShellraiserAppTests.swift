import AppKit
import XCTest
@testable import Shellraiser

/// Covers application-delegate termination wiring.
@MainActor
final class ShellraiserAppTests: WorkspaceTestCase {
    override func setUp() {
        super.setUp()
        ShellraiserScriptingController.shared.resetForTesting()
    }

    override func tearDown() {
        ShellraiserScriptingController.shared.resetForTesting()
        super.tearDown()
    }

    /// Verifies confirmed app termination freezes manager shutdown state before teardown proceeds.
    func testApplicationShouldTerminatePreparesWorkspaceManagerBeforeQuitting() {
        let manager = makeWorkspaceManager()
        ShellraiserScriptingController.shared.install(workspaceManager: manager)
        let delegate = ShellraiserAppDelegate()
        delegate.confirmQuit = { true }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertTrue(manager.isTerminating)
    }

    /// Verifies cancelled termination leaves the workspace manager untouched.
    func testApplicationShouldTerminateDoesNotPrepareWorkspaceManagerWhenCancelled() {
        let manager = makeWorkspaceManager()
        ShellraiserScriptingController.shared.install(workspaceManager: manager)
        let delegate = ShellraiserAppDelegate()
        delegate.confirmQuit = { false }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertFalse(manager.isTerminating)
    }

    /// Verifies the delegate returns true (allow reopen handling) when no windows are visible,
    /// so AppKit proceeds to make a window key — required for dock-click restoration.
    func testApplicationShouldHandleReopenReturnsTrueWithNoVisibleWindows() {
        let delegate = ShellraiserAppDelegate()
        let result = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        XCTAssertTrue(result)
    }

    /// Verifies the delegate returns true even when windows are already visible,
    /// keeping reopen handling consistent regardless of window visibility state.
    func testApplicationShouldHandleReopenReturnsTrueWithVisibleWindows() {
        let delegate = ShellraiserAppDelegate()
        let result = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        XCTAssertTrue(result)
    }
}
