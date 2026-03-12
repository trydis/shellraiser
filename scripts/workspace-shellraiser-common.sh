#!/usr/bin/env bash

# Prints an error message and exits with failure.
fail_with_message() {
    echo "$1" >&2
    exit 1
}

# Prints the standard workspace-name guidance and exits with failure.
fail_workspace_name_required() {
    fail_with_message "Workspace name is required."
}

# Returns the Git repository root for the current invocation path.
resolve_repo_root() {
    if ! git rev-parse --show-toplevel 2>/dev/null; then
        fail_with_message "This script must be run from inside a Git repository."
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

# Returns a workspace slug that is safe for Git branch and directory names.
slugify_workspace_name() {
    local workspace_name="$1"
    local slug

    slug="$(
        printf '%s' "$workspace_name" \
            | tr '[:upper:]' '[:lower:]' \
            | sed -E 's#[/[:space:]]+#-#g; s/[^a-z0-9._-]+//g; s/-+/-/g; s/^[.-]+//; s/[.-]+$//'
    )"

    if [[ -z "$slug" ]]; then
        fail_with_message "Workspace name must contain letters or numbers after sanitization."
    fi

    printf '%s\n' "$slug"
}

# Verifies the requested base branch exists locally.
ensure_local_branch_exists() {
    local repo_root="$1"
    local branch_name="$2"

    if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
        fail_with_message "Base branch '$branch_name' does not exist locally in '$repo_root'."
    fi
}

# Returns whether the requested local branch exists.
local_branch_exists() {
    local repo_root="$1"
    local branch_name="$2"

    git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"
}

# Returns the default sibling worktree path for the requested branch slug.
resolve_workspace_worktree_path() {
    local repo_root="$1"
    local branch_name="$2"
    local parent_dir repo_name

    parent_dir="$(cd "$repo_root/.." && pwd -P)"
    repo_name="$(basename "$repo_root")"

    printf '%s/%s-%s\n' "$parent_dir" "$repo_name" "$branch_name"
}

# Returns the registered worktree path for a branch, when one exists.
resolve_registered_worktree_for_branch() {
    local repo_root="$1"
    local branch_name="$2"
    local current_path=""
    local current_branch=""
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            if [[ "$current_branch" == "refs/heads/$branch_name" && -n "$current_path" ]]; then
                printf '%s\n' "$current_path"
                return 0
            fi

            current_path=""
            current_branch=""
            continue
        fi

        case "$line" in
            worktree\ *)
                current_path="${line#worktree }"
                ;;
            branch\ *)
                current_branch="${line#branch }"
                ;;
        esac
    done < <(git -C "$repo_root" worktree list --porcelain)

    if [[ "$current_branch" == "refs/heads/$branch_name" && -n "$current_path" ]]; then
        printf '%s\n' "$current_path"
    fi
}

# Returns the registered branch ref for a worktree path, when one exists.
resolve_registered_branch_for_worktree() {
    local repo_root="$1"
    local worktree_path="$2"
    local current_path=""
    local current_branch=""
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            if [[ "$current_path" == "$worktree_path" && -n "$current_branch" ]]; then
                printf '%s\n' "$current_branch"
                return 0
            fi

            current_path=""
            current_branch=""
            continue
        fi

        case "$line" in
            worktree\ *)
                current_path="${line#worktree }"
                ;;
            branch\ *)
                current_branch="${line#branch }"
                ;;
        esac
    done < <(git -C "$repo_root" worktree list --porcelain)

    if [[ "$current_path" == "$worktree_path" && -n "$current_branch" ]]; then
        printf '%s\n' "$current_branch"
    fi
}

# Creates or reuses a linked worktree for the workspace and prints `<path><tab><branch>`.
prepare_workspace_worktree() {
    local repo_root="$1"
    local workspace_name="$2"
    local branch_name worktree_path existing_worktree_path registered_branch

    repo_root="$(cd "$repo_root" && pwd -P)"
    branch_name="$(slugify_workspace_name "$workspace_name")"
    worktree_path="$(resolve_workspace_worktree_path "$repo_root" "$branch_name")"

    ensure_local_branch_exists "$repo_root" "main"

    existing_worktree_path="$(resolve_registered_worktree_for_branch "$repo_root" "$branch_name")"
    registered_branch="$(resolve_registered_branch_for_worktree "$repo_root" "$worktree_path")"

    if local_branch_exists "$repo_root" "$branch_name"; then
        if [[ -z "$existing_worktree_path" ]]; then
            fail_with_message "Branch '$branch_name' already exists but is not checked out at '$worktree_path'."
        fi

        if [[ "$existing_worktree_path" != "$worktree_path" ]]; then
            fail_with_message "Branch '$branch_name' is already checked out at '$existing_worktree_path', not '$worktree_path'."
        fi

        printf '%s\t%s\n' "$worktree_path" "$branch_name"
        return 0
    fi

    if [[ -n "$registered_branch" ]]; then
        fail_with_message "Worktree path '$worktree_path' is already registered for '$registered_branch'."
    fi

    if [[ -e "$worktree_path" ]]; then
        fail_with_message "Worktree path '$worktree_path' already exists and is not a registered Git worktree."
    fi

    if ! git -C "$repo_root" worktree add -b "$branch_name" "$worktree_path" main >/dev/null; then
        fail_with_message "Failed to create worktree '$worktree_path' from base branch 'main'."
    fi

    printf '%s\t%s\n' "$worktree_path" "$branch_name"
}

# Creates a new Shellraiser workspace rooted at the worktree and starts the two commands.
run_shellraiser_workspace_with_commands() {
    local workspace_root="$1"
    local workspace_name="$2"
    local left_command="$3"
    local right_command="$4"

    if ! osascript - "$workspace_root" "$workspace_name" "$left_command" "$right_command" <<'APPLESCRIPT'
on run argv
    set workspaceRoot to item 1 of argv
    set workspaceName to item 2 of argv
    set leftCommand to item 3 of argv
    set rightCommand to item 4 of argv

    tell application "Shellraiser"
        set config to new surface configuration
        set initial working directory of config to workspaceRoot

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
        fail_with_message "Shellraiser automation failed. Ensure Shellraiser is installed and supports scripting."
    fi
}
