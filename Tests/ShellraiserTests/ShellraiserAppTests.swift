import AppKit
import XCTest
@testable import Shellraiser

/// Covers application-delegate termination wiring.
@MainActor
final class ShellraiserAppTests: WorkspaceTestCase {
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
}
