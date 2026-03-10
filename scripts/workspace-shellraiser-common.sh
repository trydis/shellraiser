#!/usr/bin/env bash

# Prints the standard workspace-name guidance and exits with failure.
fail_workspace_name_required() {
    echo "Workspace name is required." >&2
    exit 1
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
        if ! read -r -p "Workspace name: " workspace_name; then
            fail_workspace_name_required
        fi
    fi

    if [[ -z "${workspace_name//[[:space:]]/}" ]]; then
        fail_workspace_name_required
    fi

    printf '%s\n' "$workspace_name"
}

# Creates a new Shellraiser workspace rooted at the repo and starts the two commands.
run_shellraiser_workspace_with_commands() {
    local repo_root="$1"
    local workspace_name="$2"
    local left_command="$3"
    local right_command="$4"

    if ! osascript - "$repo_root" "$workspace_name" "$left_command" "$right_command" <<'APPLESCRIPT'
on run argv
    set repoRoot to item 1 of argv
    set workspaceName to item 2 of argv
    set leftCommand to item 3 of argv
    set rightCommand to item 4 of argv

    tell application "Shellraiser"
        set config to new surface configuration
        set initial working directory of config to repoRoot

        set ws to new workspace named workspaceName with configuration config
        set leftTerminal to first terminal of selected tab of ws
        set rightTerminal to split terminal leftTerminal direction right with configuration config

        input text leftCommand to leftTerminal
        send key "enter" to leftTerminal

        input text rightCommand to rightTerminal
        send key "enter" to rightTerminal
    end tell
end run
APPLESCRIPT
    then
        echo "Shellraiser automation failed. Ensure Shellraiser is installed and supports scripting." >&2
        exit 1
    fi
}
