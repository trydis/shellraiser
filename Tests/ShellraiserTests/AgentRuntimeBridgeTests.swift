import XCTest
@testable import Shellraiser

/// Covers managed-agent wrapper generation for runtime integration.
@MainActor
final class AgentRuntimeBridgeTests: XCTestCase {
    /// Creates a bridge rooted in a unique temporary directory for test isolation.
    private func makeBridge(testName: String = #function) throws -> AgentRuntimeBridge {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellraiserTests-\(sanitizedTestName)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        return AgentRuntimeBridge(rootURL: directory)
    }

    /// Verifies environment assembly stays local and does not require synchronous executable lookup.
    func testEnvironmentInjectsManagedWrapperVariablesWithoutResolvedBinaryPaths() throws {
        let bridge = try makeBridge()
        let surfaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!

        let environment = bridge.environment(
            for: surfaceId,
            shellPath: "/bin/zsh",
            baseEnvironment: [
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "TERM": "xterm-256color"
            ]
        )

        XCTAssertEqual(
            environment["PATH"],
            "\(bridge.binDirectory.path):/usr/local/bin:/usr/bin:/bin"
        )
        XCTAssertEqual(environment["TERM"], "xterm-256color")
        XCTAssertEqual(environment["SHELLRAISER_EVENT_LOG"], bridge.eventLogURL.path)
        XCTAssertEqual(environment["SHELLRAISER_SURFACE_ID"], surfaceId.uuidString)
        XCTAssertEqual(
            environment["SHELLRAISER_HELPER_PATH"],
            bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete").path
        )
        XCTAssertEqual(environment["SHELLRAISER_COPILOT_HOME"], bridge.copilotHomeURL.path)
        XCTAssertEqual(environment["ZDOTDIR"], bridge.zshShimDirectory.path)
        XCTAssertEqual(environment["SHELLRAISER_WRAPPER_BIN"], bridge.binDirectory.path)
        XCTAssertEqual(environment["SHELLRAISER_ORIGINAL_PATH"], "/usr/local/bin:/usr/bin:/bin")
        XCTAssertNil(environment["SHELLRAISER_REAL_CLAUDE"])
        XCTAssertNil(environment["SHELLRAISER_REAL_CODEX"])
        XCTAssertNil(environment["SHELLRAISER_REAL_COPILOT"])
    }

    /// Verifies the Claude wrapper emits start, stop, permission-request, and selected notification hooks.
    func testPrepareRuntimeSupportWritesClaudeWrapperWithMappedNotificationHooks() throws {
        let bridge = try makeBridge()
        let wrapperURL = bridge.binDirectory.appendingPathComponent("claude")

        bridge.prepareRuntimeSupport()

        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)

        XCTAssertTrue(wrapperContents.contains("\"SessionStart\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"startup\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"resume\""))
        XCTAssertTrue(wrapperContents.contains("\"UserPromptSubmit\""))
        XCTAssertTrue(wrapperContents.contains("\"PreToolUse\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"*\""))
        XCTAssertTrue(wrapperContents.contains("\"Stop\""))
        XCTAssertTrue(wrapperContents.contains("\"PermissionRequest\""))
        XCTAssertTrue(wrapperContents.contains("\"Notification\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"permission_prompt\""))
        XCTAssertTrue(wrapperContents.contains("\"matcher\": \"elicitation_dialog\""))
        XCTAssertTrue(wrapperContents.contains("claudeCode \"$surface\" exited"))
        XCTAssertFalse(wrapperContents.contains("\"SubagentStop\""))
        // PermissionRequest and Notification hooks must emit waiting-for-input, not completed.
        XCTAssertTrue(wrapperContents.contains("waiting-for-input"))
    }

    /// Verifies the helper script only matches fully qualified managed runtime phases.
    func testPrepareRuntimeSupportWritesHelperWithoutBareRuntimeCases() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")
        let lockURL = bridge.runtimeDirectory.appendingPathComponent("agent-completions.log.lock")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        XCTAssertTrue(helperContents.contains("codex:session|claudeCode:session|copilot:session)"))
        XCTAssertTrue(helperContents.contains("claudeCode:hook-session|codex:hook-session)"))
        XCTAssertTrue(helperContents.contains("copilot:hook-session)"))
        XCTAssertTrue(helperContents.contains("\"sessionId\""))
        XCTAssertTrue(helperContents.contains("session_id=\"\""))
        XCTAssertTrue(helperContents.contains("if [ \"$phase\" = \"session\" ] && [ -z \"$session_id\" ]; then"))
        XCTAssertTrue(helperContents.contains("/usr/bin/lockf"))
        XCTAssertTrue(helperContents.contains("${SHELLRAISER_EVENT_LOG}.lock"))
        XCTAssertFalse(helperContents.contains("\n            codex)\n"))
        XCTAssertFalse(helperContents.contains("codex:completed)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }

    /// Verifies runtime wrappers emit session identity metadata for later resume.
    func testPrepareRuntimeSupportWritesWrappersWithSessionIdentityCapture() throws {
        let bridge = try makeBridge()
        let claudeWrapperURL = bridge.binDirectory.appendingPathComponent("claude")
        let codexWrapperURL = bridge.binDirectory.appendingPathComponent("codex")
        let copilotWrapperURL = bridge.binDirectory.appendingPathComponent("copilot")
        let copilotHookManagerURL = bridge.binDirectory.appendingPathComponent("shellraiser-copilot-hooks")

        bridge.prepareRuntimeSupport()

        let claudeWrapperContents = try String(contentsOf: claudeWrapperURL, encoding: .utf8)
        let codexWrapperContents = try String(contentsOf: codexWrapperURL, encoding: .utf8)
        let copilotWrapperContents = try String(contentsOf: copilotWrapperURL, encoding: .utf8)
        let copilotHookManagerContents = try String(contentsOf: copilotHookManagerURL, encoding: .utf8)

        // Claude wrapper: hook-based session and lifecycle
        XCTAssertTrue(claudeWrapperContents.contains("hook-session"))
        XCTAssertTrue(claudeWrapperContents.contains("lookup_path=\"${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}\""))
        XCTAssertTrue(claudeWrapperContents.contains("PATH=\"$lookup_path\" /usr/bin/which claude"))
        XCTAssertFalse(claudeWrapperContents.contains("SHELLRAISER_PREFERRED_CLAUDE_SESSION_ID"))
        XCTAssertFalse(claudeWrapperContents.contains("--session-id"))
        XCTAssertTrue(claudeWrapperContents.contains("claudeCode \"$surface\" exited"))

        // Codex wrapper: uses native inline hooks (same as 0e76333), PermissionRequest → waiting-for-input
        XCTAssertTrue(codexWrapperContents.contains("\"$real\" --help 2>&1 | /usr/bin/grep -Fq -- \"--dangerously-bypass-hook-trust\""))
        XCTAssertFalse(codexWrapperContents.contains("            --dangerously-bypass-hook-trust \\"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.SessionStart"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.UserPromptSubmit"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.PreToolUse"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.PermissionRequest"))
        XCTAssertTrue(codexWrapperContents.contains("hooks.Stop"))
        XCTAssertTrue(codexWrapperContents.contains(#"command=\"\\\"$helper\\\" codex \\\"$surface\\\" hook-session\""#))
        XCTAssertTrue(codexWrapperContents.contains(#"command=\"\\\"$helper\\\" codex \\\"$surface\\\" started\""#))
        XCTAssertTrue(codexWrapperContents.contains(#"command=\"\\\"$helper\\\" codex \\\"$surface\\\" waiting-for-input\""#))
        XCTAssertTrue(codexWrapperContents.contains(#"command=\"\\\"$helper\\\" codex \\\"$surface\\\" completed\""#))
        XCTAssertTrue(codexWrapperContents.contains(#""$helper" codex "$surface" exited"#))
        XCTAssertTrue(codexWrapperContents.contains("lookup_path=\"${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}\""))
        XCTAssertTrue(codexWrapperContents.contains("PATH=\"$lookup_path\" /usr/bin/which codex"))
        XCTAssertFalse(codexWrapperContents.contains("monitor_codex_session"))
        XCTAssertFalse(codexWrapperContents.contains("extract_codex_session_timestamp"))
        XCTAssertFalse(codexWrapperContents.contains("normalize_codex_session_timestamp"))
        XCTAssertFalse(codexWrapperContents.contains("monitor_pid"))
        XCTAssertFalse(codexWrapperContents.contains("notify_config"))

        // Copilot: managed user hook file with a supervised, crash-recoverable lease.
        XCTAssertTrue(copilotWrapperContents.contains("SHELLRAISER_REAL_COPILOT"))
        XCTAssertTrue(copilotWrapperContents.contains("PATH=\"$lookup_path\" /usr/bin/which copilot"))
        XCTAssertTrue(copilotWrapperContents.contains("\"$manager\" acquire \"$$\""))
        XCTAssertTrue(copilotWrapperContents.contains("\"$manager\" replace \"$lease\" \"$child\""))
        XCTAssertTrue(copilotWrapperContents.contains("\"$helper\" copilot \"$surface\" exited"))
        XCTAssertTrue(copilotWrapperContents.contains("\"$real\" \"$@\" < /dev/tty &"))
        XCTAssertTrue(copilotWrapperContents.contains("/bin/kill \"-$signal\" \"$child\""))
        XCTAssertTrue(copilotWrapperContents.contains("wait \"$child\" || true"))
        XCTAssertTrue(copilotHookManagerContents.contains("shellraiser-managed.json"))
        XCTAssertTrue(copilotHookManagerContents.contains("\"sessionStart\""))
        XCTAssertTrue(copilotHookManagerContents.contains("\"userPromptSubmitted\""))
        XCTAssertTrue(copilotHookManagerContents.contains("\"preToolUse\""))
        XCTAssertTrue(copilotHookManagerContents.contains("\"agentStop\""))
        XCTAssertTrue(copilotHookManagerContents.contains("\"sessionEnd\""))
        XCTAssertTrue(copilotHookManagerContents.contains("permission_prompt|elicitation_dialog"))
        XCTAssertTrue(copilotHookManagerContents.contains("copilot-leases"))
        XCTAssertTrue(copilotHookManagerContents.contains("fingerprint"))
        XCTAssertTrue(copilotHookManagerContents.contains("/usr/bin/lockf"))
    }

    /// Verifies the zsh shim sources Ghostty shell integration when the runtime is active.
    ///
    /// The `.zshrc` shim must source `ghostty-integration` from `$GHOSTTY_RESOURCES_DIR`
    /// so that Ghostty's shell-integration features (title, CWD, marks) work inside
    /// Shellraiser-managed surfaces.
    func testPrepareRuntimeSupportWritesZshRcShimWithGhosttyIntegrationSourcing() throws {
        let bridge = try makeBridge()
        let zshRcURL = bridge.zshShimDirectory.appendingPathComponent(".zshrc")

        bridge.prepareRuntimeSupport()

        let zshRcContents = try String(contentsOf: zshRcURL, encoding: .utf8)

        XCTAssertTrue(zshRcContents.contains("GHOSTTY_RESOURCES_DIR"))
        XCTAssertTrue(zshRcContents.contains("ghostty-integration"))
        XCTAssertTrue(zshRcContents.contains("shell-integration/zsh/ghostty-integration"))
    }

    /// Verifies the helper can extract session identifiers from hook payloads for all runtimes.
    func testPrepareRuntimeSupportWritesHelperWithHookSessionParsing() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)

        // Both runtimes share the same sed-based JSON extraction via a unified case branch.
        XCTAssertTrue(helperContents.contains("claudeCode:hook-session|codex:hook-session)"))
        XCTAssertTrue(helperContents.contains("\"session_id\""))
        XCTAssertTrue(helperContents.contains("\"transcript_path\""))
        XCTAssertTrue(helperContents.contains("copilot:hook-session"))
        XCTAssertTrue(helperContents.contains("\"sessionId\""))
        XCTAssertFalse(helperContents.contains("/usr/bin/python3"))
        XCTAssertTrue(helperContents.contains("phase=\"session\""))
    }

    /// Verifies Copilot's notification hook signals waiting-for-input, not completed.
    ///
    /// A blocked Copilot permission prompt must not be reported as a finished turn.
    /// The generated hook dispatches a `notification` phase (with stdout suppressed,
    /// since Copilot parses hook stdout as JSON and would otherwise inject any
    /// `additionalContext` into the session), and the helper reclassifies it to
    /// `waiting-for-input` by parsing the payload's `notification_type` field,
    /// failing open (trusting the hook's own matcher) when stdin is unavailable.
    func testPrepareRuntimeSupportWritesCopilotNotificationHookAsWaitingForInput() throws {
        let bridge = try makeBridge()
        let helperURL = bridge.binDirectory.appendingPathComponent("shellraiser-agent-complete")
        let copilotHookManagerURL = bridge.binDirectory.appendingPathComponent("shellraiser-copilot-hooks")

        bridge.prepareRuntimeSupport()

        let helperContents = try String(contentsOf: helperURL, encoding: .utf8)
        let copilotHookManagerContents = try String(contentsOf: copilotHookManagerURL, encoding: .utf8)

        // The notification hook must preserve its matcher and dispatch "notification",
        // not hardcode "completed", and must not leak anything onto stdout.
        XCTAssertTrue(copilotHookManagerContents.contains("permission_prompt|elicitation_dialog"))
        XCTAssertTrue(copilotHookManagerContents.contains(#"copilot \"$SHELLRAISER_SURFACE_ID\" notification > /dev/null"#))

        // The helper must classify the notification payload's notification_type field
        // and fail open to waiting-for-input when it can't be determined.
        XCTAssertTrue(helperContents.contains("copilot:notification)"))
        XCTAssertTrue(helperContents.contains("\"notification_type\""))
        XCTAssertTrue(helperContents.contains("shell_completed|shell_detached_completed|agent_completed|agent_idle)"))
        XCTAssertTrue(helperContents.contains("phase=\"waiting-for-input\""))
        XCTAssertTrue(helperContents.contains("started|completed|session|exited|hook-session|waiting-for-input|notification)"))
    }
}

