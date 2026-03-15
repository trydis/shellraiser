import Foundation

/// App-owned runtime bridge that installs helper binaries for agent completion hooks.
@MainActor
final class AgentRuntimeBridge: AgentRuntimeSupporting {
    static let shared = AgentRuntimeBridge()

    let runtimeDirectory: URL
    let binDirectory: URL
    let teamBinDirectory: URL
    let zshShimDirectory: URL
    let eventLogURL: URL

    private let fileManager: FileManager
    private let tmuxShimExecutableURLOverride: URL?
    private let allowsTmuxShimDiscovery: Bool
    private var cachedExecutablePaths: [String: String?] = [:]

    /// Creates the bridge rooted in the process temp directory to avoid path escaping issues.
    private convenience init() {
        self.init(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "ShellraiserRuntime",
                isDirectory: true
            )
        )
    }

    /// Creates a bridge rooted in the supplied directory for isolated runtime support.
    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        tmuxShimExecutableURLOverride: URL? = nil,
        allowsTmuxShimDiscovery: Bool = true
    ) {
        self.fileManager = fileManager
        self.runtimeDirectory = rootURL
        self.binDirectory = rootURL.appendingPathComponent("bin", isDirectory: true)
        self.teamBinDirectory = rootURL.appendingPathComponent("team-bin", isDirectory: true)
        self.zshShimDirectory = rootURL.appendingPathComponent("zsh", isDirectory: true)
        self.eventLogURL = rootURL.appendingPathComponent("agent-completions.log")
        self.tmuxShimExecutableURLOverride = tmuxShimExecutableURLOverride
        self.allowsTmuxShimDiscovery = allowsTmuxShimDiscovery
        prepareRuntimeSupport()
    }

    /// Ensures helper scripts and the completion event log exist.
    func prepareRuntimeSupport() {
        do {
            try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: teamBinDirectory, withIntermediateDirectories: true)
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
            try removeExecutableIfPresent(named: "tmux", in: binDirectory)
            if let tmuxShimExecutableURL = resolvedTmuxShimExecutableURL() {
                try writeExecutable(
                    named: "tmux",
                    contents: tmuxWrapperContents(realShimPath: tmuxShimExecutableURL.path),
                    in: teamBinDirectory
                )
            } else {
                try removeExecutableIfPresent(named: "tmux", in: teamBinDirectory)
            }
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

        let tmuxWrapperURL = teamBinDirectory.appendingPathComponent("tmux")
        if fileManager.isExecutableFile(atPath: tmuxWrapperURL.path) {
            environment["SHELLRAISER_TEAM_BIN"] = teamBinDirectory.path
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

    /// Resolves the tmux shim executable that should be exposed only inside Shellraiser-managed terminals.
    private func resolvedTmuxShimExecutableURL() -> URL? {
        if let override = tmuxShimExecutableURLOverride,
           fileManager.isExecutableFile(atPath: override.path) {
            return override
        }

        guard allowsTmuxShimDiscovery else { return nil }

        if let environmentOverride = ProcessInfo.processInfo.environment["SHELLRAISER_TMUX_SHIM"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentOverride.isEmpty,
           fileManager.isExecutableFile(atPath: environmentOverride) {
            return URL(fileURLWithPath: environmentOverride)
        }

        let seedURLs = candidateTmuxShimSearchRoots()
        let candidateRelativePaths = [
            ".build/arm64-apple-macosx/debug/tmux",
            ".build/arm64-apple-macosx/release/tmux",
            ".build/debug/tmux",
            ".build/release/tmux"
        ]

        for seedURL in seedURLs {
            for candidateRelativePath in candidateRelativePaths {
                let candidateURL = seedURL.appendingPathComponent(candidateRelativePath)
                if fileManager.isExecutableFile(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }

        return nil
    }

    /// Returns likely repository roots that may contain a built tmux shim binary.
    private func candidateTmuxShimSearchRoots() -> [URL] {
        var seenPaths = Set<String>()
        var roots: [URL] = []

        func appendIfNew(_ url: URL?) {
            guard let standardizedURL = url?.standardizedFileURL else { return }
            let path = standardizedURL.path
            guard seenPaths.insert(path).inserted else { return }
            roots.append(standardizedURL)
        }

        func appendBoundedAncestors(of url: URL?, limit: Int) {
            guard limit > 0 else { return }

            var currentURL = url?.standardizedFileURL
            for _ in 0..<limit {
                guard let unwrappedURL = currentURL else { break }
                appendIfNew(unwrappedURL)

                let parentURL = unwrappedURL.deletingLastPathComponent().standardizedFileURL
                if parentURL.path == unwrappedURL.path {
                    break
                }
                currentURL = parentURL
            }
        }

        appendBoundedAncestors(of: Bundle.main.bundleURL, limit: 8)
        appendBoundedAncestors(of: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), limit: 8)

        if let executablePath = ProcessInfo.processInfo.arguments.first,
           executablePath.hasPrefix("/") {
            appendBoundedAncestors(of: URL(fileURLWithPath: executablePath), limit: 8)
        }

        return roots
    }

    /// Writes an executable helper script if contents have changed.
    private func writeExecutable(named name: String, contents: String, in directoryURL: URL? = nil) throws {
        let targetDirectoryURL = directoryURL ?? binDirectory
        let fileURL = targetDirectoryURL.appendingPathComponent(name)
        try writeTextFile(at: fileURL, contents: contents)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fileURL.path
        )
    }

    /// Removes one managed executable if it exists at the supplied runtime path.
    private func removeExecutableIfPresent(named name: String, in directoryURL: URL) throws {
        let fileURL = directoryURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
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
            started|completed|session|exited|hook-session)
                ;;
            *)
                exit 0
                ;;
        esac

        case "$runtime:$phase" in
            codex:completed)
                payload="${4:-}"
                ;;
            codex:session|claudeCode:session)
                payload="${4:-}"
                ;;
            claudeCode:hook-session)
                hook_payload="$(cat)"
                compact_payload="$(printf '%s' "$hook_payload" | tr -d '\n')"
                session_id="$(printf '%s' "$compact_payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr '[:upper:]' '[:lower:]' | sed -n '1p')"
                transcript_path="$(printf '%s' "$compact_payload" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')"
                payload="$(printf '%s\n%s' "$session_id" "$transcript_path")"
                phase="session"
                ;;
        esac

        if [ "$phase" = "session" ] && [ -z "$payload" ]; then
            exit 0
        fi

        timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        encoded="$(printf '%s' "$payload" | /usr/bin/base64 | tr -d '\n')"
        printf '%s\t%s\t%s\t%s\t%s\n' "$timestamp" "$runtime" "$surface" "$phase" "$encoded" >> "${SHELLRAISER_EVENT_LOG}"
        """#
    }

    /// Claude wrapper that injects managed activity hooks for the current surface.
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
        if [ -n "${SHELLRAISER_TEAM_BIN:-}" ]; then
            export PATH="${SHELLRAISER_TEAM_BIN}:${PATH}"
        fi

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

        parse_codex_session_id() {
            case "${1:-}" in
                resume|fork)
                    shift
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            --*)
                                shift
                                ;;
                            *)
                                printf '%s\n' "$1"
                                return 0
                                ;;
                        esac
                    done
                    ;;
            esac

            return 1
        }

        codex_is_interactive_start() {
            case "${1:-}" in
                ""|-*|resume|fork)
                    return 0
                    ;;
                exec|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|cloud|features|help)
                    return 1
                    ;;
                *)
                    return 0
                    ;;
            esac
        }

        monitor_codex_session() {
            root="${HOME}/.codex/sessions"
            cwd="$(pwd)"
            stamp_file="$1"
            start_timestamp="$2"
            helper_path="$3"
            surface_id="$4"

            [ -d "$root" ] || exit 0

            extract_codex_session_timestamp() {
                session_line="$1"
                payload_timestamp="$(
                    printf '%s\n' "$session_line" \
                        | sed -n 's/.*"timestamp":"[^"]*".*"timestamp":"\([^"]*\)".*/\1/p' \
                        | head -n 1
                )"
                if [ -n "$payload_timestamp" ]; then
                    printf '%s\n' "$payload_timestamp"
                    return 0
                fi

                printf '%s\n' "$session_line" \
                    | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' \
                    | head -n 1
            }

            normalize_codex_session_timestamp() {
                timestamp="${1:-}"
                case "$timestamp" in
                    *.*Z)
                        base="${timestamp%%.*}"
                        fraction="${timestamp#*.}"
                        fraction="${fraction%Z}"
                        ;;
                    *Z)
                        base="${timestamp%Z}"
                        fraction=""
                        ;;
                    *)
                        printf '%s\n' "$timestamp"
                        return 0
                        ;;
                esac

                fraction="$(printf '%-9.9s' "$fraction" | tr ' ' '0')"
                printf '%s.%sZ\n' "$base" "$fraction"
            }

            timestamp_is_at_or_after() {
                candidate_timestamp="$(normalize_codex_session_timestamp "$1")"
                baseline_timestamp="$(normalize_codex_session_timestamp "$2")"
                latest_timestamp="$(
                    LC_ALL=C printf '%s\n%s\n' "$candidate_timestamp" "$baseline_timestamp" \
                        | LC_ALL=C sort \
                        | tail -n 1
                )"
                [ "$latest_timestamp" = "$candidate_timestamp" ]
            }

            while :; do
                [ -f "$stamp_file" ] || exit 0

                while IFS= read -r session_file; do
                    [ -f "$session_file" ] || continue
                    first_line="$(sed -n '1p' "$session_file" 2>/dev/null || true)"
                    if ! printf '%s\n' "$first_line" | grep -F "\"cwd\":\"$cwd\"" >/dev/null; then
                        continue
                    fi

                    session_timestamp="$(extract_codex_session_timestamp "$first_line")"
                    if [ -n "$session_timestamp" ] && ! timestamp_is_at_or_after "$session_timestamp" "$start_timestamp"; then
                        continue
                    fi

                    session_id="$(
                        printf '%s\n' "$first_line" \
                            | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
                            | head -n 1
                    )"
                    if [ -n "$session_id" ]; then
                        "$helper_path" codex "$surface_id" session "$session_id" || true
                        exit 0
                    fi
                done <<EOF
        $(find "$root" -type f -name 'rollout-*.jsonl' -newer "$stamp_file" -print 2>/dev/null | sort -r)
        EOF

                sleep 0.5
            done
        }

        session_id="$(parse_codex_session_id "$@" || true)"
        if [ -n "$session_id" ]; then
            "$helper" codex "$surface" session "$session_id" || true
        elif codex_is_interactive_start "${1:-}"; then
            stamp_file="${TMPDIR:-/tmp}/schmux-codex-${surface}-$$.stamp"
            start_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            : > "$stamp_file"
            monitor_codex_session "$stamp_file" "$start_timestamp" "$helper" "$surface" >/dev/null 2>&1 &
            monitor_pid="$!"
        fi

        notify_config="notify=[\"$SHELLRAISER_HELPER_PATH\",\"codex\",\"$SHELLRAISER_SURFACE_ID\",\"completed\"]"
        set +e
        "$real" -c "$notify_config" "$@"
        status=$?
        set -e
        if [ -n "${monitor_pid:-}" ]; then
            rm -f "$stamp_file"
            wait_attempts=0
            while kill -0 "$monitor_pid" 2>/dev/null && [ "$wait_attempts" -lt 10 ]; do
                sleep 0.1
                wait_attempts=$((wait_attempts + 1))
            done
            if kill -0 "$monitor_pid" 2>/dev/null; then
                kill "$monitor_pid" 2>/dev/null || true
            fi
            wait "$monitor_pid" 2>/dev/null || true
        fi
        "$helper" codex "$surface" exited || true
        exit "$status"
        """#
    }

    /// tmux wrapper that forwards to the Shellraiser-specific shim binary when available.
    private func tmuxWrapperContents(realShimPath: String) -> String {
        #"""
        #!/bin/sh
        set -eu

        real="${SHELLRAISER_REAL_TMUX_SHIM:-__REAL_TMUX_SHIM__}"
        if [ -z "$real" ] || [ ! -x "$real" ]; then
            echo "Shellraiser could not resolve the tmux shim binary." >&2
            exit 127
        fi

        exec "$real" "$@"
        """#
            .replacingOccurrences(of: "__REAL_TMUX_SHIM__", with: realShimPath)
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
