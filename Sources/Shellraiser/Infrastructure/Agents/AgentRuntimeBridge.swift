import Foundation
import Dispatch

/// App-owned runtime bridge that installs helper binaries for agent completion hooks.
@MainActor
final class AgentRuntimeBridge: AgentRuntimeSupporting {
    static let shared = AgentRuntimeBridge()

    let runtimeDirectory: URL
    let binDirectory: URL
    let zshShimDirectory: URL
    let eventLogURL: URL
    let copilotHomeURL: URL

    private let fileManager: FileManager

    /// Creates the bridge rooted in the process temp directory to avoid path escaping issues.
    private convenience init() {
        self.init(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "ShellraiserRuntime",
                isDirectory: true
            ),
            copilotHomeURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".copilot", isDirectory: true)
        )
    }

    /// Creates a bridge rooted in the supplied directory for isolated runtime support.
    init(
        rootURL: URL,
        copilotHomeURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.runtimeDirectory = rootURL
        self.binDirectory = rootURL.appendingPathComponent("bin", isDirectory: true)
        self.zshShimDirectory = rootURL.appendingPathComponent("zsh", isDirectory: true)
        self.eventLogURL = rootURL.appendingPathComponent("agent-completions.log")
        self.copilotHomeURL = copilotHomeURL
            ?? rootURL.appendingPathComponent("copilot-home", isDirectory: true)
        prepareRuntimeSupport()
        scheduleCopilotHookLeaseReap()
    }

    /// Ensures helper scripts and the completion event log exist.
    func prepareRuntimeSupport() {
        do {
            try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: zshShimDirectory, withIntermediateDirectories: true)

            if !fileManager.fileExists(atPath: eventLogURL.path) {
                fileManager.createFile(atPath: eventLogURL.path, contents: Data())
            }

            if !fileManager.fileExists(atPath: eventLogLockURL.path) {
                fileManager.createFile(atPath: eventLogLockURL.path, contents: Data())
            }

            try writeExecutable(
                named: "shellraiser-agent-complete",
                contents: helperScriptContents
            )
            try writeExecutable(
                named: "claude",
                contents: claudeWrapperContents
            )
            try writeExecutable(
                named: "codex",
                contents: codexWrapperContents
            )
            try writeExecutable(
                named: "copilot",
                contents: copilotWrapperContents
            )
            try writeExecutable(
                named: "shellraiser-copilot-hooks",
                contents: copilotHookManagerContents
            )
            try writeTextFile(
                at: zshShimDirectory.appendingPathComponent(".zshenv"),
                contents: zshEnvContents
            )
            try writeTextFile(
                at: zshShimDirectory.appendingPathComponent(".zprofile"),
                contents: zshProfileContents
            )
            try writeTextFile(
                at: zshShimDirectory.appendingPathComponent(".zshrc"),
                contents: zshRcContents
            )
            try writeTextFile(
                at: zshShimDirectory.appendingPathComponent(".zlogin"),
                contents: zshLoginContents
            )
        } catch {
            NSLog("Failed to prepare Shellraiser agent runtime bridge: \(error)")
        }
    }

    /// Builds terminal environment values that inject managed agent wrappers for a surface.
    func environment(
        for surfaceId: UUID,
        shellPath: String,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        prepareRuntimeSupport()

        var environment = baseEnvironment
        let inheritedPath = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        let wrapperPath = [binDirectory.path, inheritedPath]
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        environment["PATH"] = wrapperPath
        environment["SHELLRAISER_EVENT_LOG"] = eventLogURL.path
        environment["SHELLRAISER_SURFACE_ID"] = surfaceId.uuidString
        environment["SHELLRAISER_HELPER_PATH"] = binDirectory.appendingPathComponent("shellraiser-agent-complete").path
        environment["SHELLRAISER_COPILOT_HOME"] = copilotHomeURL.path

        if shellPath.hasSuffix("/zsh") || shellPath == "zsh" {
            environment["ZDOTDIR"] = zshShimDirectory.path
            environment["SHELLRAISER_WRAPPER_BIN"] = binDirectory.path
            environment["SHELLRAISER_ORIGINAL_PATH"] = inheritedPath
        }

        return environment
    }

    /// Writes an executable helper script if contents have changed.
    private func writeExecutable(named name: String, contents: String) throws {
        let fileURL = binDirectory.appendingPathComponent(name)
        try writeTextFile(at: fileURL, contents: contents)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fileURL.path
        )
    }

    /// Writes a text file only when contents have changed.
    private func writeTextFile(at fileURL: URL, contents: String) throws {
        let data = Data(contents.utf8)

        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return
        }

        try data.write(to: fileURL, options: .atomic)
    }

    /// Schedules one startup cleanup pass without delaying managed surface creation.
    private func scheduleCopilotHookLeaseReap() {
        let managerURL = binDirectory.appendingPathComponent("shellraiser-copilot-hooks")
        let runtimeDirectory = self.runtimeDirectory
        let environment = ProcessInfo.processInfo.environment.merging(
            ["SHELLRAISER_COPILOT_HOME": copilotHomeURL.path]
        ) { _, bridgeValue in bridgeValue }

        DispatchQueue.global(qos: .utility).async {
            guard FileManager.default.isExecutableFile(atPath: managerURL.path) else {
                return
            }

            do {
                try Self.reapCopilotHookLeases(
                    managerURL: managerURL,
                    environment: environment
                )
            } catch {
                guard FileManager.default.fileExists(atPath: runtimeDirectory.path) else {
                    return
                }
                NSLog("Failed to reap stale Shellraiser Copilot hook leases: \(error)")
            }
        }
    }

    /// Reaps stale Copilot hook leases without touching user-owned hook files.
    nonisolated private static func reapCopilotHookLeases(
        managerURL: URL,
        environment: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = managerURL
        process.arguments = ["reap"]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Returns the advisory lock file shared by helper writers and the monitor compactor.
    private var eventLogLockURL: URL {
        eventLogURL.appendingPathExtension("lock")
    }

    /// Shell helper that appends normalized activity events to the shared event log.
    private var helperScriptContents: String {
        #"""
        #!/bin/sh
        set -eu

        runtime="${1:-unknown}"
        surface="${2:-}"
        phase="${3:-}"

        if [ -z "${SHELLRAISER_EVENT_LOG:-}" ] || [ -z "$surface" ] || [ -z "$phase" ]; then
            exit 0
        fi

        payload=""
        session_id=""
        case "$phase" in
            started|completed|session|exited|hook-session)
                ;;
            *)
                exit 0
                ;;
        esac

        case "$runtime:$phase" in
            codex:session|claudeCode:session|copilot:session)
                payload="${4:-}"
                session_id="$payload"
                ;;
            claudeCode:hook-session|codex:hook-session)
                hook_payload="$(cat)"
                compact_payload="$(printf '%s' "$hook_payload" | tr -d '\n')"
                session_id="$(printf '%s' "$compact_payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | sed -n '1p')"
                transcript_path="$(printf '%s' "$compact_payload" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
                payload="$(printf '%s\n%s' "$session_id" "$transcript_path")"
                phase="session"
                ;;
            copilot:hook-session)
                hook_payload="$(cat)"
                compact_payload="$(printf '%s' "$hook_payload" | tr -d '\n')"
                session_id="$(printf '%s' "$compact_payload" | sed -n 's/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
                payload="$session_id"
                phase="session"
                ;;
        esac

        if [ "$phase" = "session" ] && [ -z "$session_id" ]; then
            exit 0
        fi

        timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        encoded="$(printf '%s' "$payload" | /usr/bin/base64 | tr -d '\n')"
        lock_file="${SHELLRAISER_EVENT_LOG}.lock"
        /usr/bin/lockf "$lock_file" /bin/sh -c 'printf "%s\t%s\t%s\t%s\t%s\n" "$2" "$3" "$4" "$5" "$6" >> "$1"' sh "${SHELLRAISER_EVENT_LOG}" "$timestamp" "$runtime" "$surface" "$phase" "$encoded"
        """#
    }

    /// Claude wrapper that injects managed activity hooks for the current surface.
    private var claudeWrapperContents: String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_CLAUDE:-}"
        lookup_path="${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}"
        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            real="$(PATH="$lookup_path" /usr/bin/which claude 2>/dev/null || true)"
        fi

        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            echo "Shellraiser could not resolve the real Claude binary." >&2
            exit 127
        fi

        helper="${SHELLRAISER_HELPER_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/shellraiser-agent-complete}"
        surface="${SHELLRAISER_SURFACE_ID:-}"

        if [ -z "$surface" ] || [ ! -x "$helper" ]; then
            exec "$real" "$@"
        fi

        export SHELLRAISER_HELPER_PATH="$helper"
        export SHELLRAISER_SURFACE_ID="$surface"

        settings_file="${TMPDIR:-/tmp}/schmux-claude-${surface}-$$.json"
        cleanup() {
            rm -f "$settings_file"
        }
        trap cleanup EXIT INT TERM

        cat > "$settings_file" <<EOF
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "startup",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" hook-session"
                  }
                ]
              },
              {
                "matcher": "resume",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" hook-session"
                  }
                ]
              }
            ],
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" started"
                  }
                ]
              }
            ],
            "PreToolUse": [
              {
                "matcher": "*",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" started"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" completed"
                  }
                ]
              }
            ],
            "PermissionRequest": [
              {
                "matcher": "*",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" completed"
                  }
                ]
              }
            ],
            "Notification": [
              {
                "matcher": "permission_prompt",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" completed"
                  }
                ]
              },
              {
                "matcher": "elicitation_dialog",
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$SHELLRAISER_HELPER_PATH\" claudeCode \"$SHELLRAISER_SURFACE_ID\" completed"
                  }
                ]
              }
            ]
          }
        }
        EOF

        set +e
        "$real" --settings "$settings_file" "$@"
        status=$?
        set -e
        "$helper" claudeCode "$surface" exited || true
        exit "$status"
        """#
    }

    /// Codex wrapper that injects native activity hooks for the current surface.
    private var codexWrapperContents: String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_CODEX:-}"
        lookup_path="${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}"
        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            real="$(PATH="$lookup_path" /usr/bin/which codex 2>/dev/null || true)"
        fi

        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            echo "Shellraiser could not resolve the real Codex binary." >&2
            exit 127
        fi

        helper="${SHELLRAISER_HELPER_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/shellraiser-agent-complete}"
        surface="${SHELLRAISER_SURFACE_ID:-}"

        if [ -z "$surface" ] || [ ! -x "$helper" ]; then
            exec "$real" "$@"
        fi

        export SHELLRAISER_HELPER_PATH="$helper"
        export SHELLRAISER_SURFACE_ID="$surface"

        if ! "$real" --help 2>&1 | /usr/bin/grep -Fq -- "--dangerously-bypass-hook-trust"; then
            exec "$real" "$@"
        fi

        set +e
        "$real" \
            -c "hooks.SessionStart=[{hooks=[{type=\"command\",command=\"\\\"$helper\\\" codex \\\"$surface\\\" hook-session\"}]}]" \
            -c "hooks.UserPromptSubmit=[{hooks=[{type=\"command\",command=\"\\\"$helper\\\" codex \\\"$surface\\\" started\"}]}]" \
            -c "hooks.PreToolUse=[{matcher=\"*\",hooks=[{type=\"command\",command=\"\\\"$helper\\\" codex \\\"$surface\\\" started\"}]}]" \
            -c "hooks.PermissionRequest=[{matcher=\"*\",hooks=[{type=\"command\",command=\"\\\"$helper\\\" codex \\\"$surface\\\" completed\"}]}]" \
            -c "hooks.Stop=[{hooks=[{type=\"command\",command=\"\\\"$helper\\\" codex \\\"$surface\\\" completed\"}]}]" \
            "$@"
        status=$?
        set -e
        "$helper" codex "$surface" exited || true
        exit "$status"
        """#
    }

    /// Copilot CLI wrapper that installs Shellraiser-owned lifecycle hooks while it supervises a session.
    private var copilotWrapperContents: String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_COPILOT:-}"
        lookup_path="${SHELLRAISER_ORIGINAL_PATH:-${PATH:-}}"
        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            real="$(PATH="$lookup_path" /usr/bin/which copilot 2>/dev/null || true)"
        fi

        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            echo "Shellraiser could not resolve the real Copilot CLI binary." >&2
            exit 127
        fi

        helper="${SHELLRAISER_HELPER_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/shellraiser-agent-complete}"
        manager="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/shellraiser-copilot-hooks"
        surface="${SHELLRAISER_SURFACE_ID:-}"

        if [ -z "$surface" ] || [ ! -x "$helper" ] || [ ! -x "$manager" ]; then
            exec "$real" "$@"
        fi

        export SHELLRAISER_HELPER_PATH="$helper"
        export SHELLRAISER_SURFACE_ID="$surface"

        if ! lease="$("$manager" acquire "$$")"; then
            echo "Shellraiser could not install its Copilot lifecycle hooks; starting Copilot without managed tracking." >&2
            exec "$real" "$@"
        fi

        cleanup() {
            "$manager" release "$lease" >/dev/null 2>&1 || true
        }
        child=""
        terminate() {
            signal="$1"
            status="$2"
            if [ -n "$child" ]; then
                /bin/kill "-$signal" "$child" 2>/dev/null || true
                wait "$child" || true
            fi
            cleanup
            exit "$status"
        }
        trap 'terminate HUP 129' HUP
        trap 'terminate INT 130' INT
        trap 'terminate TERM 143' TERM

        set +e
        "$real" "$@" < /dev/tty &
        child=$!
        "$manager" replace "$lease" "$child" >/dev/null 2>&1 || true
        wait "$child"
        status=$?
        set -e
        "$helper" copilot "$surface" exited || true
        cleanup
        exit "$status"
        """#
    }

    /// Shared, lock-protected manager for the temporary Copilot user hook file and process leases.
    private var copilotHookManagerContents: String {
        #"""
        #!/bin/sh
        set -eu

        home="${SHELLRAISER_COPILOT_HOME:-${COPILOT_HOME:-$HOME/.copilot}}"
        hook_dir="$home/hooks"
        state_dir="$home/shellraiser"
        hook_file="$hook_dir/shellraiser-managed.json"
        leases_file="$state_dir/copilot-leases"
        lock_file="$state_dir/copilot-hooks.lock"
        action="${1:-}"

        fingerprint() {
            /bin/ps -o lstart= -p "$1" 2>/dev/null | /usr/bin/tr -d ' ' || true
        }

        is_live() {
            [ -n "$2" ] && [ "$(fingerprint "$1")" = "$2" ]
        }

        write_hook_file() {
            /bin/mkdir -p "$hook_dir"
            /bin/cat > "$hook_file" <<'EOF'
        {
          "version": 1,
          "hooks": {
            "sessionStart": [{"type": "command", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" hook-session; fi", "timeoutSec": 5}],
            "userPromptSubmitted": [{"type": "command", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" started; fi", "timeoutSec": 5}],
            "preToolUse": [{"type": "command", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" started; fi", "timeoutSec": 5}],
            "agentStop": [{"type": "command", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" completed; fi", "timeoutSec": 5}],
            "notification": [{"type": "command", "matcher": "permission_prompt|elicitation_dialog", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" completed; fi", "timeoutSec": 5}],
            "sessionEnd": [{"type": "command", "bash": "if [ -n \"${SHELLRAISER_HELPER_PATH:-}\" ] && [ -n \"${SHELLRAISER_SURFACE_ID:-}\" ]; then \"$SHELLRAISER_HELPER_PATH\" copilot \"$SHELLRAISER_SURFACE_ID\" exited; fi", "timeoutSec": 5}]
          }
        }
        EOF
        }

        reap() {
            : > "$leases_file.next"
            if [ -f "$leases_file" ]; then
                while IFS='|' read -r token pid started; do
                    if is_live "$pid" "$started"; then
                        printf '%s|%s|%s\n' "$token" "$pid" "$started" >> "$leases_file.next"
                    fi
                done < "$leases_file"
            fi
            /bin/mv "$leases_file.next" "$leases_file"
            if [ ! -s "$leases_file" ]; then
                /bin/rm -f "$hook_file"
            fi
        }

        locked() {
            /bin/mkdir -p "$state_dir"
            reap
            case "$action" in
                acquire)
                    pid="$1"
                    started="$(fingerprint "$pid")"
                    [ -n "$started" ] || exit 1
                    token="$pid-$(date +%s)-${RANDOM:-0}"
                    printf '%s|%s|%s\n' "$token" "$pid" "$started" >> "$leases_file"
                    write_hook_file
                    printf '%s\n' "$token"
                    ;;
                replace)
                    token="$1"
                    pid="$2"
                    started="$(fingerprint "$pid")"
                    [ -n "$started" ] || exit 1
                    /usr/bin/awk -F'|' -v token="$token" -v pid="$pid" -v started="$started" 'BEGIN { OFS="|" } $1 == token { print token, pid, started; next } { print }' "$leases_file" > "$leases_file.next"
                    /bin/mv "$leases_file.next" "$leases_file"
                    ;;
                release)
                    token="$1"
                    /usr/bin/awk -F'|' -v token="$token" '$1 != token' "$leases_file" > "$leases_file.next"
                    /bin/mv "$leases_file.next" "$leases_file"
                    reap
                    ;;
                reap)
                    ;;
                *)
                    exit 64
                    ;;
            esac
        }

        if [ "$action" = "locked" ]; then
            shift
            action="${1:-}"
            shift
            locked "$@"
        else
            /bin/mkdir -p "$state_dir"
            /usr/bin/lockf "$lock_file" /bin/sh -c '"$@"' sh "$0" locked "$@"
        fi
        """#
    }

    /// zsh shim that sources the user's original `.zshenv` and reapplies Shellraiser runtime vars.
    private var zshEnvContents: String {
        #"""
        if [ -f "$HOME/.zshenv" ]; then
            source "$HOME/.zshenv"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_REAL_COPILOT SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves user login config and reapplies the wrapper path afterwards.
    private var zshProfileContents: String {
        #"""
        if [ -f "$HOME/.zprofile" ]; then
            source "$HOME/.zprofile"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_REAL_COPILOT SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves user interactive config and reapplies the wrapper path afterwards.
    private var zshRcContents: String {
        #"""
        if [ -f "$HOME/.zshrc" ]; then
            source "$HOME/.zshrc"
        fi

        if [[ -n "$GHOSTTY_RESOURCES_DIR" ]] && [[ -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
            source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_REAL_COPILOT SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves any user `.zlogin` behavior.
    private var zshLoginContents: String {
        #"""
        if [ -f "$HOME/.zlogin" ]; then
            source "$HOME/.zlogin"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_REAL_COPILOT SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }
}
