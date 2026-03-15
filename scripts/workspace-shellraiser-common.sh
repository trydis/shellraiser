#!/usr/bin/env bash

# Prints an error message and exits with failure.
fail_with_message() {
    echo "$1" >&2
    if [[ "${SHELLRAISER_SCRIPT_SOURCED:-0}" == "1" ]]; then
        return 1
    fi

    exit 1
}

# Prints the standard workspace-name guidance and exits with failure.
fail_workspace_name_required() {
    fail_with_message "Workspace name is required."
}

# Prints the standard worktree-name guidance and exits with failure.
fail_worktree_name_required() {
    fail_with_message "Worktree name is required."
}

# Returns the Git repository root for the current invocation path.
resolve_repo_root() {
    if ! git rev-parse --show-toplevel 2>/dev/null; then
        fail_with_message "This script must be run from inside a Git repository."
    fi
}

# Returns the canonical primary repository root even when invoked from a linked worktree.
resolve_main_repo_root() {
    local repo_root="${1:-}"
    local common_git_dir

    if [[ -n "$repo_root" ]]; then
        repo_root="$(cd "$repo_root" && pwd -P)"
        if common_git_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
            :
        else
            fail_with_message "Failed to resolve the repository common Git directory."
            return 1
        fi
    elif common_git_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
        :
    else
        repo_root="$(resolve_repo_root)"
        if ! common_git_dir="$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null)"; then
            fail_with_message "Failed to resolve the repository common Git directory."
            return 1
        fi
        if [[ "$common_git_dir" != /* ]]; then
            common_git_dir="$repo_root/$common_git_dir"
        fi
    fi

    if ! cd "$common_git_dir/.." >/dev/null 2>&1; then
        fail_with_message "Failed to resolve the canonical repository root."
        return 1
    fi

    pwd -P
}

# Returns the requested workspace name from arguments or an interactive prompt.
resolve_workspace_name() {
    local workspace_name

    if (($# > 0)); then
        workspace_name="$*"
    else
        printf '%s' "Workspace name: "
        if ! read -r workspace_name; then
            fail_workspace_name_required
        fi
    fi

    if [[ -z "${workspace_name//[[:space:]]/}" ]]; then
        fail_workspace_name_required
    fi

    printf '%s\n' "$workspace_name"
}

# Returns the requested worktree name from arguments or an interactive prompt.
resolve_worktree_name() {
    local worktree_name

    if (($# > 0)); then
        worktree_name="$*"
    else
        printf '%s' "Worktree name: "
        if ! read -r worktree_name; then
            fail_worktree_name_required
        fi
    fi

    if [[ -z "${worktree_name//[[:space:]]/}" ]]; then
        fail_worktree_name_required
    fi

    printf '%s\n' "$worktree_name"
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
        return 1
    fi

    if ! git check-ref-format --branch "$slug" >/dev/null 2>&1; then
        slug="$(
            printf '%s' "$slug" \
                | sed -E 's/\.\.+/./g; s/(\.lock)+$//; s/^[.-]+//; s/[.-]+$//'
        )"
    fi

    if [[ -z "$slug" ]]; then
        fail_with_message "Workspace name '$workspace_name' cannot be converted to a Git-safe slug."
        return 1
    fi

    if ! git check-ref-format --branch "$slug" >/dev/null 2>&1; then
        fail_with_message "Workspace name '$workspace_name' cannot be converted to a Git-safe slug."
        return 1
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

# Returns whether the requested worktree path is registered with Git.
registered_worktree_exists() {
    local repo_root="$1"
    local worktree_path="$2"

    [[ -n "$(resolve_registered_branch_for_worktree "$repo_root" "$worktree_path")" ]]
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

# Creates or reuses a linked worktree for the workspace and prints `<path><tab><branch><tab><status>`.
prepare_workspace_worktree_with_status() {
    local repo_root="$1"
    local workspace_name="$2"
    local main_repo_root branch_name worktree_path existing_worktree_path registered_branch

    repo_root="$(cd "$repo_root" && pwd -P)" || return 1
    main_repo_root="$(resolve_main_repo_root "$repo_root")" || return 1
    [[ -n "$main_repo_root" ]] || {
        fail_with_message "Failed to resolve the canonical repository root for '$repo_root'."
        return 1
    }

    branch_name="$(slugify_workspace_name "$workspace_name")" || return 1
    [[ -n "$branch_name" ]] || {
        fail_with_message "Failed to derive a branch name for workspace '$workspace_name'."
        return 1
    }

    worktree_path="$(resolve_workspace_worktree_path "$main_repo_root" "$branch_name")" || return 1
    [[ -n "$worktree_path" ]] || {
        fail_with_message "Failed to resolve the worktree path for branch '$branch_name'."
        return 1
    }

    ensure_local_branch_exists "$main_repo_root" "main" || return 1

    existing_worktree_path="$(resolve_registered_worktree_for_branch "$main_repo_root" "$branch_name")"
    registered_branch="$(resolve_registered_branch_for_worktree "$main_repo_root" "$worktree_path")"

    if local_branch_exists "$main_repo_root" "$branch_name"; then
        if [[ -z "$existing_worktree_path" ]]; then
            fail_with_message "Branch '$branch_name' already exists but is not checked out at '$worktree_path'."
            return 1
        fi

        if [[ "$existing_worktree_path" != "$worktree_path" ]]; then
            fail_with_message "Branch '$branch_name' is already checked out at '$existing_worktree_path', not '$worktree_path'."
            return 1
        fi

        printf '%s\t%s\texisting\n' "$worktree_path" "$branch_name"
        return 0
    fi

    if [[ -n "$registered_branch" ]]; then
        fail_with_message "Worktree path '$worktree_path' is already registered for '$registered_branch'."
        return 1
    fi

    if [[ -e "$worktree_path" ]]; then
        fail_with_message "Worktree path '$worktree_path' already exists and is not a registered Git worktree."
        return 1
    fi

    if ! git -C "$main_repo_root" worktree add -b "$branch_name" "$worktree_path" main >/dev/null; then
        fail_with_message "Failed to create worktree '$worktree_path' from base branch 'main'."
        return 1
    fi

    printf '%s\t%s\tcreated\n' "$worktree_path" "$branch_name"
}

# Creates or reuses a linked worktree for the workspace and prints `<path><tab><branch>`.
prepare_workspace_worktree() {
    local worktree_path branch_name worktree_status

    IFS=$'\t' read -r worktree_path branch_name worktree_status < <(
        prepare_workspace_worktree_with_status "$@"
    )
    [[ -n "$worktree_path" && -n "$branch_name" && -n "$worktree_status" ]] \
        || fail_with_message "Failed to resolve the workspace worktree."

    printf '%s\t%s\n' "$worktree_path" "$branch_name"
}

# Initializes the Ghostty submodule and builds the native XCFramework for a new worktree.
bootstrap_ghostty_for_worktree() {
    local worktree_root="$1"
    local ghostty_root="$worktree_root/ghostty"

    printf 'Initializing ghostty submodule in %s\n' "$worktree_root"
    if ! (
        cd "$worktree_root" &&
        git submodule update --init --recursive ghostty
    ); then
        fail_with_message "Failed to initialize the 'ghostty' submodule in '$worktree_root'."
        return 1
    fi

    if [[ ! -d "$ghostty_root" ]]; then
        fail_with_message "Ghostty submodule directory '$ghostty_root' was not created."
        return 1
    fi

    if ! command -v zig >/dev/null 2>&1; then
        fail_with_message "Required command 'zig' was not found in PATH."
        return 1
    fi

    printf 'Building Ghostty XCFramework in %s\n' "$ghostty_root"
    if ! (
        cd "$ghostty_root" &&
        zig build \
            -Demit-xcframework=true \
            -Demit-macos-app=false \
            -Dxcframework-target=native \
            -Doptimize=ReleaseFast
    ); then
        fail_with_message "Failed to build Ghostty XCFramework in '$ghostty_root'."
        return 1
    fi
}

# Prompts the user for an interactive yes/no confirmation.
confirm_with_user() {
    local prompt_message="$1"
    local response=""

    printf '%s' "$prompt_message [y/N] "
    if ! read -r response; then
        return 1
    fi

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Returns whether a linked worktree is clean enough for non-forced removal.
worktree_is_clean() {
    local worktree_path="$1"
    local status_output

    status_output="$(git -C "$worktree_path" status --porcelain --untracked-files=all --ignore-submodules=none)"
    [[ -z "$status_output" ]]
}

# Returns whether safe branch deletion would require force.
branch_delete_requires_force() {
    local repo_root="$1"
    local branch_name="$2"
    local upstream_ref target_ref

    upstream_ref="$(git -C "$repo_root" for-each-ref --format='%(upstream:short)' "refs/heads/$branch_name")"
    target_ref="${upstream_ref:-HEAD}"

    if git -C "$repo_root" merge-base --is-ancestor "$branch_name" "$target_ref" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Removes a linked worktree, optionally prompting before forcing removal of dirty contents.
remove_workspace_worktree() {
    local repo_root="$1"
    local main_repo_root="$2"
    local worktree_path="$3"
    local force_mode="${4:-prompt}"

    if [[ "$worktree_path" == "$main_repo_root" ]]; then
        fail_with_message "Refusing to remove the primary repository worktree '$worktree_path'."
        return 1
    fi

    if ! registered_worktree_exists "$repo_root" "$worktree_path"; then
        return 1
    fi

    if worktree_is_clean "$worktree_path"; then
        if ! git -C "$repo_root" worktree remove "$worktree_path"; then
            fail_with_message "Failed to remove clean worktree '$worktree_path'."
            return 1
        fi
        return 0
    fi

    if [[ "$force_mode" == "prompt" ]] && ! confirm_with_user "Worktree '$worktree_path' has uncommitted or untracked files. Force delete it?"; then
        return 1
    fi

    git -C "$repo_root" worktree remove -f "$worktree_path" \
        || fail_with_message "Failed to force-remove worktree '$worktree_path'."
}

# Deletes a branch, optionally prompting before forcing removal when Git refuses a safe delete.
delete_workspace_branch() {
    local repo_root="$1"
    local branch_name="$2"
    local force_mode="${3:-prompt}"

    if ! local_branch_exists "$repo_root" "$branch_name"; then
        return 1
    fi

    if git -C "$repo_root" branch -d "$branch_name"; then
        return 0
    fi

    if [[ "$force_mode" == "prompt" ]] && ! confirm_with_user "Branch '$branch_name' was not deleted safely. Force delete it?"; then
        return 1
    fi

    git -C "$repo_root" branch -D "$branch_name" \
        || fail_with_message "Failed to force-delete branch '$branch_name'."
}

# Deletes the matching Shellraiser workspace for a stable workspace root path.
delete_shellraiser_workspace_for_root() {
    local workspace_root="$1"
    local result

    if ! pgrep -x "Shellraiser" >/dev/null 2>&1; then
        printf '%s\n' "not-running"
        return 0
    fi

    if ! result="$(osascript - "$workspace_root" <<'APPLESCRIPT'
on run argv
    set workspaceRoot to item 1 of argv

    tell application "Shellraiser"
        set matchingWorkspaces to every workspace whose root working directory is workspaceRoot
        set matchCount to count of matchingWorkspaces

        if matchCount = 0 then
            return "not-found"
        end if

        if matchCount > 1 then
            error "Multiple Shellraiser workspaces match " & workspaceRoot
        end if

        delete workspace (item 1 of matchingWorkspaces)
        return "deleted"
    end tell
end run
APPLESCRIPT
    )"; then
        fail_with_message "Shellraiser workspace deletion failed for '$workspace_root'."
    fi

    printf '%s\n' "$result"
}

# Creates a new Shellraiser workspace rooted at the worktree and starts the two commands.
run_shellraiser_workspace_with_commands() {
    local workspace_root="$1"
    local workspace_name="$2"
    local left_command="$3"
    local right_command="$4"
    local automation_result

    if ! automation_result="$(
        osascript - "$workspace_root" "$workspace_name" "$left_command" "$right_command" 2>&1 <<'APPLESCRIPT'
on run argv
    set workspaceRoot to item 1 of argv
    set workspaceName to item 2 of argv
    set leftCommand to item 3 of argv
    set rightCommand to item 4 of argv

    tell application "Shellraiser"
        set config to new surface configuration
        set initial working directory of config to workspaceRoot

        set matchingWorkspaces to every workspace whose root working directory is workspaceRoot
        set matchCount to count of matchingWorkspaces

        if matchCount > 1 then
            error "Multiple Shellraiser workspaces match " & workspaceRoot
        end if

        if matchCount = 1 then
            error "A Shellraiser workspace already exists for " & workspaceRoot
        end if

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
    )"; then
        fail_with_message "${automation_result:-Shellraiser automation failed. Ensure Shellraiser is installed and supports scripting.}"
    fi
}
