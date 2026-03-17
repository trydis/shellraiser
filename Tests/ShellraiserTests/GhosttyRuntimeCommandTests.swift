#if canImport(GhosttyKit)
import XCTest
@testable import Shellraiser

/// Covers terminal launch command construction for Ghostty surfaces.
@MainActor
final class GhosttyRuntimeCommandTests: XCTestCase {
    /// Verifies Shellraiser passes the shell directly without a working-directory wrapper.
    ///
    /// Working directory is delegated to Ghostty via `config.working_directory`; no
    /// `/bin/sh -lc "cd …"` wrapper is needed.
    func testLaunchCommandWrapsShellWithWorkingDirectoryChange() {
        let config = TerminalPanelConfig(
            workingDirectory: "/tmp/project",
            shell: "/bin/zsh",
            environment: [:]
        )

        let command = GhosttyRuntime.launchCommand(for: config)
        XCTAssertEqual(command, "'/bin/zsh'")
        XCTAssertFalse(command.contains("/bin/sh"))
        XCTAssertFalse(command.contains("cd --"))
        XCTAssertFalse(command.contains("/tmp/project"))
    }

    /// Verifies working directory is not embedded in the launch command regardless of its value.
    ///
    /// Ghostty receives the working directory via its own config channel; the launch command
    /// only carries the shell path.
    func testLaunchCommandPreservesUntrimmedWorkingDirectoryInWrapper() {
        let config = TerminalPanelConfig(
            workingDirectory: "  /tmp/project with spaces  ",
            shell: "/bin/zsh",
            environment: [:]
        )

        let command = GhosttyRuntime.launchCommand(for: config)
        XCTAssertEqual(command, "'/bin/zsh'")
        XCTAssertFalse(command.contains("/tmp/project with spaces"))
    }

    /// Verifies whitespace-only working directories are treated as unspecified.
    func testLaunchCommandTreatsWhitespaceOnlyWorkingDirectoryAsUnset() {
        let config = TerminalPanelConfig(
            workingDirectory: "   \n\t  ",
            shell: "/bin/zsh",
            environment: [:]
        )

        let command = GhosttyRuntime.launchCommand(for: config)
        XCTAssertEqual(command, "'/bin/zsh'")
    }

    /// Verifies surfaces with persisted session identifiers relaunch into agent resume commands.
    func testLaunchCommandUsesResumeCommandWhenSurfaceHasPersistedSessionId() {
        let surface = SurfaceModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            title: "~",
            agentType: .codex,
            sessionId: "019ce8bb-b369-7693-9be0-664a228e4e24",
            shouldResumeSession: true,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp/project",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let command = GhosttyRuntime.launchCommand(for: surface, terminalConfig: surface.terminalConfig)
        XCTAssertTrue(command.contains("codex"))
        XCTAssertTrue(command.contains("resume"))
        XCTAssertTrue(command.contains("019ce8bb-b369-7693-9be0-664a228e4e24"))
        XCTAssertFalse(command.contains("/bin/zsh"))
    }

    /// Verifies Claude only relaunches with resume when its persisted transcript exists on disk.
    func testLaunchCommandUsesClaudeResumeWhenTranscriptExists() throws {
        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-Claude-\(UUID().uuidString).jsonl")
        try Data().write(to: transcriptURL)
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        let surface = SurfaceModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            title: "~",
            agentType: .claudeCode,
            sessionId: "da38c283-06c0-4d30-aada-c9552606d76a",
            transcriptPath: transcriptURL.path,
            shouldResumeSession: true,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp/project",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let command = GhosttyRuntime.launchCommand(for: surface, terminalConfig: surface.terminalConfig)
        let claudeRange = command.range(of: "claude")
        let resumeRange = command.range(of: "--resume")
        XCTAssertNotNil(claudeRange)
        XCTAssertNotNil(resumeRange)
        XCTAssertLessThan(claudeRange?.lowerBound ?? command.endIndex, resumeRange?.lowerBound ?? command.startIndex)
        XCTAssertTrue(command.contains("da38c283-06c0-4d30-aada-c9552606d76a"))
        XCTAssertFalse(command.contains("/bin/zsh"))
    }

    /// Verifies Claude falls back to a shell launch when no persisted transcript exists to resume.
    func testLaunchCommandFallsBackToShellWhenClaudeTranscriptIsMissing() {
        let surface = SurfaceModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!,
            title: "~",
            agentType: .claudeCode,
            sessionId: "da38c283-06c0-4d30-aada-c9552606d76a",
            transcriptPath: "/tmp/does-not-exist-\(UUID().uuidString).jsonl",
            shouldResumeSession: true,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp/project",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let command = GhosttyRuntime.launchCommand(for: surface, terminalConfig: surface.terminalConfig)
        XCTAssertTrue(command.contains("/bin/zsh"))
        XCTAssertFalse(command.contains("--resume"))
    }

    /// Verifies persisted session ids are ignored when a surface is not marked resumable.
    func testLaunchCommandIgnoresStoredSessionWhenResumeEligibilityIsFalse() {
        let surface = SurfaceModel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            title: "~",
            agentType: .codex,
            sessionId: "019ce8bb-b369-7693-9be0-664a228e4e24",
            shouldResumeSession: false,
            terminalConfig: TerminalPanelConfig(
                workingDirectory: "/tmp/project",
                shell: "/bin/zsh",
                environment: [:]
            ),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let command = GhosttyRuntime.launchCommand(for: surface, terminalConfig: surface.terminalConfig)
        XCTAssertTrue(command.contains("/bin/zsh"))
        XCTAssertFalse(command.contains("resume"))
    }
}
#endif
