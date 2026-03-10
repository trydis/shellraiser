import Foundation

/// App-owned runtime bridge that installs helper binaries for agent completion hooks.
@MainActor
final class AgentRuntimeBridge: AgentRuntimeSupporting {
    static let shared = AgentRuntimeBridge()

    let runtimeDirectory: URL
    let binDirectory: URL
    let zshShimDirectory: URL
    let eventLogURL: URL

    private let fileManager = FileManager.default
    private var cachedExecutablePaths: [String: String?] = [:]

    /// Creates the bridge rooted in the process temp directory to avoid path escaping issues.
    private init() {
        let runtimeDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "ShellraiserRuntime",
            isDirectory: true
        )
        self.runtimeDirectory = runtimeDirectory
        self.binDirectory = runtimeDirectory.appendingPathComponent("bin", isDirectory: true)
        self.zshShimDirectory = runtimeDirectory.appendingPathComponent("zsh", isDirectory: true)
        self.eventLogURL = runtimeDirectory.appendingPathComponent("agent-completions.log")

        prepareRuntimeSupport()
    }

    /// Ensures helper scripts and the completion event log exist.
    func prepareRuntimeSupport() {
        do {
            try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: zshShimDirectory, withIntermediateDirectories: true)

            if !fileManager.fileExists(atPath: eventLogURL.path) {
                fileManager.createFile(atPath: eventLogURL.path, contents: Data())
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

        if shellPath.hasSuffix("/zsh") || shellPath == "zsh" {
            environment["ZDOTDIR"] = zshShimDirectory.path
            environment["SHELLRAISER_WRAPPER_BIN"] = binDirectory.path
            environment["SHELLRAISER_ORIGINAL_PATH"] = inheritedPath
        }

        if let claudePath = resolveExecutable(named: "claude", searchPath: inheritedPath) {
            environment["SHELLRAISER_REAL_CLAUDE"] = claudePath
        }

        if let codexPath = resolveExecutable(named: "codex", searchPath: inheritedPath) {
            environment["SHELLRAISER_REAL_CODEX"] = codexPath
        }

        return environment
    }

    /// Resolves the current machine path for an executable before wrapper PATH injection takes effect.
    private func resolveExecutable(named name: String, searchPath: String) -> String? {
        if let cached = cachedExecutablePaths[name] {
            return cached
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.environment = ["PATH": searchPath]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                cachedExecutablePaths[name] = nil
                return nil
            }

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let resolved = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = resolved.isEmpty ? nil : resolved
            cachedExecutablePaths[name] = value
            return value
        } catch {
            cachedExecutablePaths[name] = nil
            return nil
        }
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
        case "$phase" in
            started|completed)
                ;;
            *)
                exit 0
                ;;
        esac

        case "$runtime:$phase" in
            codex:completed)
                payload="${4:-}"
                ;;
            codex)
                ;;
        esac

        timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        encoded="$(printf '%s' "$payload" | /usr/bin/base64 | tr -d '\n')"
        printf '%s\t%s\t%s\t%s\t%s\n' "$timestamp" "$runtime" "$surface" "$phase" "$encoded" >> "${SHELLRAISER_EVENT_LOG}"
        """#
    }

    /// Claude wrapper that injects top-level start and stop hooks for the current surface.
    private var claudeWrapperContents: String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_CLAUDE:-}"
        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            real="$(/usr/bin/which claude 2>/dev/null || true)"
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
            "Stop": [
              {
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

        exec "$real" --settings "$settings_file" "$@"
        """#
    }

    /// Codex wrapper that injects the official `notify` callback for the current surface.
    private var codexWrapperContents: String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_CODEX:-}"
        if [ -z "$real" ] || [ "$real" = "$0" ]; then
            real="$(/usr/bin/which codex 2>/dev/null || true)"
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

        notify_config="notify=[\"$SHELLRAISER_HELPER_PATH\",\"codex\",\"$SHELLRAISER_SURFACE_ID\",\"completed\"]"
        exec "$real" -c "$notify_config" "$@"
        """#
    }

    /// zsh shim that sources the user's original `.zshenv` and reapplies Shellraiser runtime vars.
    private var zshEnvContents: String {
        #"""
        if [ -f "$HOME/.zshenv" ]; then
            source "$HOME/.zshenv"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves user login config and reapplies the wrapper path afterwards.
    private var zshProfileContents: String {
        #"""
        if [ -f "$HOME/.zprofile" ]; then
            source "$HOME/.zprofile"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves user interactive config and reapplies the wrapper path afterwards.
    private var zshRcContents: String {
        #"""
        if [ -f "$HOME/.zshrc" ]; then
            source "$HOME/.zshrc"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }

    /// zsh shim that preserves any user `.zlogin` behavior.
    private var zshLoginContents: String {
        #"""
        if [ -f "$HOME/.zlogin" ]; then
            source "$HOME/.zlogin"
        fi

        export PATH="${SHELLRAISER_WRAPPER_BIN}:${PATH:-${SHELLRAISER_ORIGINAL_PATH}}"
        export SHELLRAISER_EVENT_LOG SHELLRAISER_SURFACE_ID SHELLRAISER_HELPER_PATH SHELLRAISER_REAL_CLAUDE SHELLRAISER_REAL_CODEX SHELLRAISER_WRAPPER_BIN SHELLRAISER_ORIGINAL_PATH
        """#
    }
}
