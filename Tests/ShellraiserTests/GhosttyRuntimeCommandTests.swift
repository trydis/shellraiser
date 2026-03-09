#if canImport(GhosttyKit)
import XCTest
@testable import Shellraiser

/// Covers terminal launch command construction for Ghostty surfaces.
@MainActor
final class GhosttyRuntimeCommandTests: XCTestCase {
    /// Verifies Shellraiser wraps the requested shell with an explicit directory change.
    func testLaunchCommandWrapsShellWithWorkingDirectoryChange() {
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp/project",
            shell: "/bin/zsh",
            environment: [:]
        )

        let command = GhosttyRuntime.launchCommand(for: config)
        XCTAssertTrue(command.contains("/bin/sh"))
        XCTAssertTrue(command.contains("cd --"))
        XCTAssertTrue(command.contains("/tmp/project"))
        XCTAssertTrue(command.contains("/bin/zsh"))
    }

    /// Verifies working-directory wrapper preserves significant leading and trailing spaces.
    func testLaunchCommandPreservesUntrimmedWorkingDirectoryInWrapper() {
        let config = TerminalPanelConfig(
            workingDirectory: "  /tmp/project with spaces  ",
            shell: "/bin/zsh",
            environment: [:]
        )

        let command = GhosttyRuntime.launchCommand(for: config)
        XCTAssertTrue(command.contains("  /tmp/project with spaces  "))
    }
}
#endif
