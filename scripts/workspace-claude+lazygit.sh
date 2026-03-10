#!/usr/bin/env bash

set -euo pipefail

main() {
    local repo_root workspace_name
    repo_root="$(resolve_repo_root)"
    workspace_name="$(resolve_workspace_name "$@")"

    run_shellraiser_workspace_bootstrap "$repo_root" "$workspace_name"
}

# Returns the Git repository root for the current invocation path.
resolve_repo_root() {
    if ! git rev-parse --show-toplevel 2>/dev/null; then
        echo "This script must be run from inside a Git repository." >&2
        exit 1
    fi
}

# Returns the requested workspace name from arguments or an interactive prompt.
resolve_workspace_name() {
    local workspace_name

    if (($# > 0)); then
        workspace_name="$*"
    else
        read -r -p "Workspace name: " workspace_name
    fi

    if [[ -z "${workspace_name//[[:space:]]/}" ]]; then
        echo "Workspace name is required." >&2
        exit 1
    fi

    printf '%s\n' "$workspace_name"
}

# Creates a new Shellraiser workspace rooted at the repo and starts the two commands.
run_shellraiser_workspace_bootstrap() {
    local repo_root="$1"
    local workspace_name="$2"

    if ! osascript - "$repo_root" "$workspace_name" <<'APPLESCRIPT'
on run argv
    set repoRoot to item 1 of argv
    set workspaceName to item 2 of argv

    tell application "Shellraiser"
        set config to new surface configuration
        set initial working directory of config to repoRoot

        set ws to new workspace named workspaceName with configuration config
        set leftTerminal to first terminal of selected tab of ws
        set rightTerminal to split terminal leftTerminal direction right with configuration config

        input text "claude" to leftTerminal
        send key "enter" to leftTerminal

        input text "lazygit" to rightTerminal
        send key "enter" to rightTerminal
    end tell
end run
APPLESCRIPT
    then
        echo "Shellraiser automation failed. Ensure Shellraiser is installed and supports scripting." >&2
        exit 1
    fi
}

main "$@"
