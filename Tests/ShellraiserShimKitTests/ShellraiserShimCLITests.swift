import Foundation
import XCTest
@testable import ShellraiserShimKit

/// Covers the native Shellraiser control CLI and the tmux-compatible shim.
final class ShellraiserShimCLITests: XCTestCase {
    /// Verifies `shellraiserctl new-workspace` emits the created identifiers.
    func testShellraiserControlCLINewWorkspacePrintsCreatedIdentifiers() {
        let controller = MockShellraiserController()
        let cli = ShellraiserControlCLI(controller: controller)

        let result = cli.run(arguments: ["new-workspace", "--name", "Agent Team", "--cwd", "/tmp/project"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(controller.createdWorkspaceName, "Agent Team")
        XCTAssertEqual(controller.createdWorkspaceCWD, "/tmp/project")
        XCTAssertTrue(result.standardOutput.contains("workspace_id=workspace-1"))
        XCTAssertTrue(result.standardOutput.contains("surface_id=surface-1"))
    }

    /// Verifies `tmux new-session` persists a new session and starter pane.
    func testTmuxNewSessionCreatesWorkspaceAndTracksPane() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore()
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["new-session", "-d", "-s", "coord", "claude"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%1\n")
        XCTAssertEqual(controller.sentTextEvents.count, 1)
        XCTAssertEqual(controller.sentTextEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.sentTextEvents.first?.1, "claude")
        XCTAssertEqual(controller.sentKeyEvents.count, 1)
        XCTAssertEqual(controller.sentKeyEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.sentKeyEvents.first?.1, "enter")
        XCTAssertEqual(try store.load().sessionsByName["coord"]?.panes.map(\.paneId), ["%1"])
        XCTAssertEqual(try store.load().sessionsByName["coord"]?.ownsWorkspace, true)
    }

    /// Verifies `tmux new-session -P -F` prints the requested tmux format for Claude probes.
    func testTmuxNewSessionSupportsPrintFormatFlags() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore()
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: [
            "-L", "claude-swarm-1",
            "new-session",
            "-d",
            "-s", "claude-swarm",
            "-n", "swarm-view",
            "-P",
            "-F", "#{pane_id}"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%1\n")
        XCTAssertEqual(try store.load().socketState(named: "claude-swarm-1").sessionsByName.keys.sorted(), ["claude-swarm"])
        XCTAssertEqual(try store.load().socketState(named: "claude-swarm-1").sessionsByName["claude-swarm"]?.panes.first?.windowName, "swarm-view")
        XCTAssertTrue(controller.sentTextEvents.isEmpty)
        XCTAssertTrue(controller.sentKeyEvents.isEmpty)
    }

    /// Verifies `tmux new-session` attaches to the originating workspace when launched from a managed surface.
    func testTmuxNewSessionAttachesToOriginWorkspaceWhenSurfaceContextExists() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore()
        let cli = TmuxShimCLI(
            controller: controller,
            stateStore: store,
            environment: ["SHELLRAISER_SURFACE_ID": "surface-1"]
        )

        let result = cli.run(arguments: ["new-session", "-d", "-s", "claude-swarm", "-n", "swarm-view"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%1\n")
        XCTAssertNil(controller.createdWorkspaceName)
        XCTAssertEqual(controller.splitEvents.count, 1)
        XCTAssertEqual(controller.splitEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.splitEvents.first?.1, .right)
        XCTAssertEqual(try store.load().sessionsByName["claude-swarm"]?.workspaceId, "workspace-1")
        XCTAssertEqual(try store.load().sessionsByName["claude-swarm"]?.ownsWorkspace, false)
    }

    /// Verifies `tmux -V` succeeds for Claude's compatibility probe.
    func testTmuxVersionFlagReturnsTmuxLikeVersionString() {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore()
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["-V"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "tmux 3.4\n")
    }

    /// Verifies `tmux -L <socket> ...` keeps state isolated per socket namespace.
    func testTmuxSocketNamespacesAreTrackedIndependently() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore()
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let createResult = cli.run(arguments: ["-L", "claude-swarm-1", "new-session", "-d", "-s", "coord"])
        let foundInSocket = cli.run(arguments: ["-L", "claude-swarm-1", "has-session", "-t", "coord"])
        let missingInDefault = cli.run(arguments: ["has-session", "-t", "coord"])

        XCTAssertEqual(createResult.exitCode, 0)
        XCTAssertEqual(foundInSocket.exitCode, 0)
        XCTAssertEqual(missingInDefault.exitCode, 1)
        XCTAssertEqual(try store.load().socketState(named: "claude-swarm-1").sessionsByName.keys.sorted(), ["coord"])
    }

    /// Verifies legacy flat shim state decodes into the default socket namespace.
    func testTmuxShimStateDecodesLegacyFlatSchema() throws {
        let legacyJSON = """
        {
          "nextPaneOrdinal" : 4,
          "sessionsByName" : {
            "coord" : {
              "focusedPaneId" : "%2",
              "name" : "coord",
              "panes" : [
                {
                  "paneId" : "%2",
                  "surfaceId" : "surface-1"
                }
              ],
              "workspaceId" : "workspace-1"
            }
          },
          "version" : 1
        }
        """

        let state = try JSONDecoder().decode(TmuxShimState.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(state.socketState(named: TmuxShimState.defaultSocketName).nextPaneOrdinal, 4)
        XCTAssertEqual(state.socketState(named: TmuxShimState.defaultSocketName).sessionsByName.keys.sorted(), ["coord"])
        XCTAssertEqual(state.sessionsByName["coord"]?.focusedPaneId, "%2")
    }

    /// Verifies `tmux split-window` uses the focused pane when the target names a session.
    func testTmuxSplitWindowCreatesSiblingPane() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                nextPaneOrdinal: 2,
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["split-window", "-t", "coord", "-h", "lazygit"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%2\n")
        XCTAssertEqual(controller.splitEvents.count, 1)
        XCTAssertEqual(controller.splitEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.splitEvents.first?.1, .right)
        XCTAssertNil(controller.splitEvents.first?.2)
        XCTAssertEqual(controller.sentTextEvents.last?.0, "surface-2")
        XCTAssertEqual(try store.load().sessionsByName["coord"]?.focusedPaneId, "%2")
    }

    /// Verifies `tmux split-window -P -F` returns formatted pane output without sending stray shell text.
    func testTmuxSplitWindowSupportsPrintFormatFlags() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                nextPaneOrdinal: 2,
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1", windowName: "main")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["split-window", "-t", "%1", "-h", "-P", "-F", "#{pane_id}"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%2\n")
        XCTAssertTrue(controller.sentTextEvents.isEmpty)
        XCTAssertTrue(controller.sentKeyEvents.isEmpty)
    }

    /// Verifies `tmux send-keys` mixes literal text and special keys in order.
    func testTmuxSendKeysFlushesTextBeforeSpecialKeys() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                nextPaneOrdinal: 2,
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["send-keys", "-t", "coord", "Agent complete", "Enter", "C-c"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(controller.sentTextEvents.count, 1)
        XCTAssertEqual(controller.sentTextEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.sentTextEvents.first?.1, "Agent complete")
        XCTAssertEqual(controller.sentKeyEvents.count, 2)
        XCTAssertEqual(controller.sentKeyEvents.first?.0, "surface-1")
        XCTAssertEqual(controller.sentKeyEvents.first?.1, "enter")
        XCTAssertEqual(controller.sentKeyEvents.last?.0, "surface-1")
        XCTAssertEqual(controller.sentKeyEvents.last?.1, "ctrl-c")
    }

    /// Verifies `tmux list-panes` renders the supported format tokens.
    func testTmuxListPanesRendersFormatTokens() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                nextPaneOrdinal: 3,
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [
                            TmuxShimPane(paneId: "%1", surfaceId: "surface-1", windowName: "main"),
                            TmuxShimPane(paneId: "%2", surfaceId: "surface-2", windowName: "tools")
                        ],
                        focusedPaneId: "%2"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["list-panes", "-t", "coord", "-F", "#{pane_id} #{pane_current_path} #{window_active}"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.standardOutput,
            "%1 /tmp/project 0\n%2 /tmp/project/tools 1\n"
        )
    }

    /// Verifies `tmux list-windows` renders unique window names for one session.
    func testTmuxListWindowsRendersWindowNames() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [
                            TmuxShimPane(paneId: "%1", surfaceId: "surface-1", windowName: "swarm-view"),
                            TmuxShimPane(paneId: "%2", surfaceId: "surface-2", windowName: "worker-1"),
                            TmuxShimPane(paneId: "%3", surfaceId: "surface-3", windowName: "worker-1")
                        ],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["list-windows", "-t", "claude-swarm", "-F", "#{window_name}"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "swarm-view\nworker-1\n")
    }

    /// Verifies `tmux select-pane` tolerates styling flags used by Claude without failing.
    func testTmuxSelectPaneAcceptsStylingFlags() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%3", surfaceId: "surface-1", windowName: "swarm-view")],
                        focusedPaneId: "%3"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: [
            "select-pane",
            "-t", "%3",
            "-P", "bg=default,fg=yellow",
            "-T", "devils-advocate"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(controller.focusedSurfaceIDs, ["surface-1"])
    }

    /// Verifies `tmux new-window` creates a new pane with the requested window name.
    func testTmuxNewWindowCreatesPaneForRequestedWindow() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                nextPaneOrdinal: 2,
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1", windowName: "main")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: [
            "new-window",
            "-t", "claude-swarm",
            "-n", "swarm-view",
            "-P",
            "-F", "#{pane_id}"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%2\n")
        XCTAssertEqual(controller.splitEvents.count, 1)
        XCTAssertEqual(try store.load().sessionsByName["claude-swarm"]?.panes.last?.windowName, "swarm-view")
    }

    /// Verifies `tmux select-layout` acts as a successful no-op for layout requests.
    func testTmuxSelectLayoutActsAsNoOp() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%2", surfaceId: "surface-1", windowName: "swarm-view")],
                        focusedPaneId: "%2"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["select-layout", "-t", "claude-swarm:swarm-view", "tiled"])

        XCTAssertEqual(result.exitCode, 0)
    }

    /// Verifies `tmux set-option` acts as a successful no-op for pane styling.
    func testTmuxSetOptionActsAsNoOp() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%3", surfaceId: "surface-1", windowName: "swarm-view")],
                        focusedPaneId: "%3"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: [
            "set-option",
            "-p",
            "-t", "%3",
            "pane-border-style",
            "fg=yellow"
        ])

        XCTAssertEqual(result.exitCode, 0)
    }

    /// Verifies session:window targets resolve to the pane inside that named window.
    func testTmuxListPanesResolvesSessionWindowTargets() throws {
        let controller = MockShellraiserController(
            surfaces: [
                ShellraiserSurfaceSnapshot(
                    id: "surface-1",
                    title: "coord",
                    workingDirectory: "/tmp/project",
                    workspaceId: "workspace-1",
                    workspaceName: "claude-swarm"
                ),
                ShellraiserSurfaceSnapshot(
                    id: "surface-2",
                    title: "swarm-view",
                    workingDirectory: "/tmp/project/swarm",
                    workspaceId: "workspace-1",
                    workspaceName: "claude-swarm"
                )
            ]
        )
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [
                            TmuxShimPane(paneId: "%1", surfaceId: "surface-1", windowName: "main"),
                            TmuxShimPane(paneId: "%2", surfaceId: "surface-2", windowName: "swarm-view")
                        ],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["list-panes", "-t", "claude-swarm:swarm-view", "-F", "#{pane_id}"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "%2\n")
    }

    /// Verifies `tmux send-keys` recognizes `ctrl+x` and `ctrl-x` forms in addition to `C-x`.
    func testTmuxSendKeysRecognizesAllControlKeyPrefixForms() throws {
        let controller = MockShellraiserController()
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["send-keys", "-t", "coord", "ctrl-c", "ctrl+d", "C-z"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(controller.sentKeyEvents.map(\.1), ["ctrl-c", "ctrl-d", "ctrl-z"])
    }

    /// Verifies `tmux has-session` returns status one for stale sessions after cleanup.
    func testTmuxHasSessionDropsStaleWorkspaceMappings() {
        let controller = MockShellraiserController(workspaces: [])
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "coord": TmuxShimSession(
                        name: "coord",
                        workspaceId: "workspace-1",
                        panes: [TmuxShimPane(paneId: "%1", surfaceId: "surface-1")],
                        focusedPaneId: "%1"
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["has-session", "-t", "coord"])

        XCTAssertEqual(result.exitCode, 1)
    }

    /// Verifies `tmux kill-session` closes only spawned teammate panes when the session is attached to an existing workspace.
    func testTmuxKillSessionClosesSpawnedPanesWithoutClosingOriginWorkspace() throws {
        let controller = MockShellraiserController(
            surfaces: [
                ShellraiserSurfaceSnapshot(
                    id: "surface-1",
                    title: "lead",
                    workingDirectory: "/tmp/project",
                    workspaceId: "workspace-1",
                    workspaceName: "coord"
                ),
                ShellraiserSurfaceSnapshot(
                    id: "surface-2",
                    title: "teammate-1",
                    workingDirectory: "/tmp/project",
                    workspaceId: "workspace-1",
                    workspaceName: "coord"
                ),
                ShellraiserSurfaceSnapshot(
                    id: "surface-3",
                    title: "teammate-2",
                    workingDirectory: "/tmp/project",
                    workspaceId: "workspace-1",
                    workspaceName: "coord"
                )
            ]
        )
        let store = InMemoryTmuxShimStateStore(
            state: TmuxShimState(
                sessionsByName: [
                    "claude-swarm": TmuxShimSession(
                        name: "claude-swarm",
                        workspaceId: "workspace-1",
                        panes: [
                            TmuxShimPane(paneId: "%1", surfaceId: "surface-2", windowName: "swarm-view"),
                            TmuxShimPane(paneId: "%2", surfaceId: "surface-3", windowName: "swarm-view")
                        ],
                        focusedPaneId: "%2",
                        ownsWorkspace: false
                    )
                ]
            )
        )
        let cli = TmuxShimCLI(controller: controller, stateStore: store)

        let result = cli.run(arguments: ["kill-session", "-t", "claude-swarm"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(controller.closedSurfaceIDs, ["surface-2", "surface-3"])
        XCTAssertTrue(controller.closedWorkspaceIDs.isEmpty)
        XCTAssertTrue(try store.load().sessionsByName.isEmpty)
    }

    /// Verifies the AppleScript client emits a quoted application literal in `tell application`.
    func testAppleScriptClientInlinesApplicationLiteralInScripts() throws {
        let runner = CapturingAppleScriptRunner(
            result: "workspace-1\u{1F}Demo\u{1F}surface-1\u{1F}Demo\u{1F}/tmp"
        )
        let client = ShellraiserAppleScriptClient(
            runner: runner,
            applicationName: "Shellraiser"
        )

        _ = try client.createWorkspace(name: "Demo", workingDirectory: "/tmp")

        XCTAssertTrue(runner.lastScript?.contains("tell application \"Shellraiser\"") == true)
        XCTAssertFalse(runner.lastScript?.contains("tell application applicationName") == true)
    }

    /// Verifies surface enumeration walks workspaces through tabs before terminals.
    func testAppleScriptClientListsSurfacesThroughTabs() throws {
        let runner = CapturingAppleScriptRunner(
            result: "surface-1\u{1F}Demo\u{1F}/tmp\u{1F}workspace-1\u{1F}Demo"
        )
        let client = ShellraiserAppleScriptClient(
            runner: runner,
            applicationName: "Shellraiser"
        )

        let surfaces = try client.listSurfaces(workspaceID: nil)

        XCTAssertEqual(surfaces.count, 1)
        XCTAssertTrue(runner.lastScript?.contains("repeat with tabItem in tabs of ws") == true)
        XCTAssertTrue(runner.lastScript?.contains("repeat with term in terminals of tabItem") == true)
        XCTAssertFalse(runner.lastScript?.contains("repeat with term in terminals of ws") == true)
    }

    /// Verifies surface lookup matches UUID-like identifiers case-insensitively.
    func testAppleScriptClientResolvesSurfaceIdentifiersCaseInsensitively() throws {
        let runner = CapturingAppleScriptRunner(
            result: "abcd1234-ef56-7890-abcd-ef1234567890\u{1F}Demo\u{1F}/tmp\u{1F}workspace-1\u{1F}Demo"
        )
        let client = ShellraiserAppleScriptClient(
            runner: runner,
            applicationName: "Shellraiser"
        )

        let surface = try client.surface(withID: "ABCD1234-EF56-7890-ABCD-EF1234567890")

        XCTAssertEqual(surface?.id, "abcd1234-ef56-7890-abcd-ef1234567890")
    }

    /// Verifies split AppleScript embeds the direction as an enumeration literal.
    func testAppleScriptClientEmbedsSplitDirectionLiteral() throws {
        let runner = CapturingAppleScriptRunner(
            result: "surface-2\u{1F}Tools\u{1F}/tmp/tools"
        )
        let client = ShellraiserAppleScriptClient(
            runner: runner,
            applicationName: "Shellraiser"
        )

        _ = try client.splitSurface(id: "surface-1", direction: .right, workingDirectory: "/tmp/tools")

        XCTAssertTrue(runner.lastScript?.contains("direction right") == true)
        XCTAssertFalse(runner.lastScript?.contains("direction splitDirection") == true)
    }

    /// Verifies focus AppleScript uses the command form expected by the scripting dictionary.
    func testAppleScriptClientUsesFocusTerminalCommandForm() throws {
        let runner = CapturingAppleScriptRunner(result: "")
        let client = ShellraiserAppleScriptClient(
            runner: runner,
            applicationName: "Shellraiser"
        )

        try client.focusSurface(id: "surface-1")

        XCTAssertTrue(runner.lastScript?.contains("focus terminal targetTerminal") == true)
        XCTAssertFalse(runner.lastScript?.contains("focus targetTerminal") == true)
    }
}

/// In-memory state store used by tmux-compatible CLI tests.
private final class InMemoryTmuxShimStateStore: TmuxShimStateStoring {
    private var state: TmuxShimState

    /// Creates a store seeded with one optional initial state snapshot.
    init(state: TmuxShimState = TmuxShimState()) {
        self.state = state
    }

    /// Loads the stored state snapshot.
    func load() throws -> TmuxShimState {
        state
    }

    /// Persists the supplied state snapshot.
    func save(_ state: TmuxShimState) throws {
        self.state = state
    }

    /// Executes body against the in-memory state without a lock (single-threaded tests).
    func transact(_ body: (inout TmuxShimState) throws -> Void) throws {
        try body(&state)
    }
}

/// Test double that records native control operations without touching AppleScript.
private final class MockShellraiserController: ShellraiserControlling {
    var createdWorkspaceName: String?
    var createdWorkspaceCWD: String?
    var sentTextEvents: [(String, String)] = []
    var sentKeyEvents: [(String, String)] = []
    var splitEvents: [(String, ShellraiserSplitDirection, String?)] = []
    var focusedSurfaceIDs: [String] = []
    var closedSurfaceIDs: [String] = []
    var closedWorkspaceIDs: [String] = []
    private let workspaceSnapshots: [ShellraiserWorkspaceSnapshot]
    private let surfaceSnapshots: [ShellraiserSurfaceSnapshot]

    /// Creates a controller with overridable visible workspaces and surfaces.
    init(
        workspaces: [ShellraiserWorkspaceSnapshot]? = nil,
        surfaces: [ShellraiserSurfaceSnapshot]? = nil
    ) {
        workspaceSnapshots = workspaces ?? [
            ShellraiserWorkspaceSnapshot(id: "workspace-1", name: "coord", selectedSurfaceId: "surface-1")
        ]
        surfaceSnapshots = surfaces ?? [
            ShellraiserSurfaceSnapshot(
                id: "surface-1",
                title: "coord",
                workingDirectory: "/tmp/project",
                workspaceId: "workspace-1",
                workspaceName: "coord"
            ),
            ShellraiserSurfaceSnapshot(
                id: "surface-2",
                title: "tools",
                workingDirectory: "/tmp/project/tools",
                workspaceId: "workspace-1",
                workspaceName: "coord"
            )
        ]
    }

    /// Records workspace creation and returns a deterministic result.
    func createWorkspace(name: String, workingDirectory: String?) throws -> ShellraiserWorkspaceCreation {
        createdWorkspaceName = name
        createdWorkspaceCWD = workingDirectory
        return ShellraiserWorkspaceCreation(
            workspace: ShellraiserWorkspaceSnapshot(id: "workspace-1", name: name, selectedSurfaceId: "surface-1"),
            surface: ShellraiserSurfaceSnapshot(
                id: "surface-1",
                title: name,
                workingDirectory: workingDirectory ?? "/tmp/project",
                workspaceId: "workspace-1",
                workspaceName: name
            )
        )
    }

    /// Records surface splits and returns a deterministic sibling surface.
    func splitSurface(
        id: String,
        direction: ShellraiserSplitDirection,
        workingDirectory: String?
    ) throws -> ShellraiserSurfaceSnapshot {
        splitEvents.append((id, direction, workingDirectory))
        return ShellraiserSurfaceSnapshot(id: "surface-2", title: "tools", workingDirectory: "/tmp/project/tools")
    }

    /// Records surface focus requests.
    func focusSurface(id: String) throws {
        focusedSurfaceIDs.append(id)
    }

    /// Records literal text injection.
    func sendText(_ text: String, toSurfaceWithID id: String) throws {
        sentTextEvents.append((id, text))
    }

    /// Records named key injection.
    func sendKey(named keyName: String, toSurfaceWithID id: String) throws {
        sentKeyEvents.append((id, keyName))
    }

    /// Returns visible workspaces.
    func listWorkspaces() throws -> [ShellraiserWorkspaceSnapshot] {
        workspaceSnapshots
    }

    /// Returns visible surfaces, optionally filtered by workspace.
    func listSurfaces(workspaceID: String?) throws -> [ShellraiserSurfaceSnapshot] {
        guard let workspaceID else { return surfaceSnapshots }
        return surfaceSnapshots.filter { $0.workspaceId == workspaceID }
    }

    /// Returns one surface by identifier.
    func surface(withID id: String) throws -> ShellraiserSurfaceSnapshot? {
        surfaceSnapshots.first(where: { $0.id == id })
    }

    /// Records surface closes.
    func closeSurface(id: String) throws {
        closedSurfaceIDs.append(id)
    }

    /// Records workspace closes.
    func closeWorkspace(id: String) throws {
        closedWorkspaceIDs.append(id)
    }
}

/// AppleScript runner test double that captures the rendered script.
private final class CapturingAppleScriptRunner: AppleScriptRunning {
    private let result: String
    private(set) var lastScript: String?
    private(set) var lastArguments: [String] = []

    /// Creates a runner that returns one fixed AppleScript result.
    init(result: String) {
        self.result = result
    }

    /// Stores the rendered script and returns the configured output.
    func run(script: String, arguments: [String]) throws -> String {
        lastScript = script
        lastArguments = arguments
        return result
    }
}
