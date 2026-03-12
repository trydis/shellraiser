#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workspace-shellraiser-common.sh
source "$script_dir/workspace-shellraiser-common.sh"

main() {
    local invocation_repo_root main_repo_root workspace_name branch_name expected_worktree_path
    local registered_worktree_path registered_branch shellraiser_status worktree_status branch_status
    local worktree_force_mode branch_force_mode

    invocation_repo_root="$(resolve_repo_root)"
    main_repo_root="$(resolve_main_repo_root)"
    workspace_name="$(resolve_workspace_name "$@")"
    branch_name="$(slugify_workspace_name "$workspace_name")"
    expected_worktree_path="$(resolve_workspace_worktree_path "$main_repo_root" "$branch_name")"
    registered_worktree_path="$(resolve_registered_worktree_for_branch "$main_repo_root" "$branch_name")"
    registered_branch="$(resolve_registered_branch_for_worktree "$main_repo_root" "$expected_worktree_path")"

    if [[ -n "$registered_worktree_path" && "$registered_worktree_path" != "$expected_worktree_path" ]]; then
        fail_with_message "Branch '$branch_name' is checked out at '$registered_worktree_path', not '$expected_worktree_path'."
    fi

    if [[ -n "$registered_branch" && "$registered_branch" != "refs/heads/$branch_name" ]]; then
        fail_with_message "Worktree path '$expected_worktree_path' is registered for '$registered_branch'."
    fi

    if local_branch_exists "$main_repo_root" "$branch_name" && [[ -z "$registered_worktree_path" ]]; then
        fail_with_message "Branch '$branch_name' exists but is not checked out at '$expected_worktree_path'."
    fi

    if [[ "$expected_worktree_path" == "$main_repo_root" || "$expected_worktree_path" == "$invocation_repo_root" && "$invocation_repo_root" == "$main_repo_root" ]]; then
        fail_with_message "Refusing to delete the primary repository worktree '$main_repo_root'."
    fi

    worktree_force_mode="prompt"
    if [[ -n "$registered_worktree_path" ]] && ! worktree_is_clean "$registered_worktree_path"; then
        if ! confirm_with_user "Deleting '$workspace_name' will kill the Shellraiser session and force-remove dirty worktree '$registered_worktree_path'. Continue?"; then
            fail_with_message "Deletion cancelled."
        fi
        worktree_force_mode="force"
    fi

    branch_force_mode="prompt"
    if local_branch_exists "$main_repo_root" "$branch_name" && branch_delete_requires_force "$main_repo_root" "$branch_name"; then
        if ! confirm_with_user "Deleting '$workspace_name' will kill the Shellraiser session and force-delete unmerged branch '$branch_name'. Continue?"; then
            fail_with_message "Deletion cancelled."
        fi
        branch_force_mode="force"
    fi

    case "$(delete_shellraiser_workspace_for_root "$expected_worktree_path")" in
        deleted)
            shellraiser_status="deleted"
            ;;
        not-found)
            shellraiser_status="not found"
            ;;
        not-running)
            shellraiser_status="app not running"
            ;;
        *)
            fail_with_message "Unexpected Shellraiser deletion result for '$expected_worktree_path'."
            ;;
    esac

    if [[ -n "$registered_worktree_path" ]]; then
        if remove_workspace_worktree "$main_repo_root" "$main_repo_root" "$registered_worktree_path" "$worktree_force_mode"; then
            worktree_status="deleted"
        else
            worktree_status="kept"
        fi
    else
        worktree_status="not found"
    fi

    if [[ "$worktree_status" == "kept" ]]; then
        branch_status="kept"
    elif local_branch_exists "$main_repo_root" "$branch_name"; then
        if delete_workspace_branch "$main_repo_root" "$branch_name" "$branch_force_mode"; then
            branch_status="deleted"
        else
            branch_status="kept"
        fi
    else
        branch_status="not found"
    fi

    printf 'Workspace: %s\n' "$workspace_name"
    printf 'Shellraiser workspace: %s\n' "$shellraiser_status"
    printf 'Git worktree: %s\n' "$worktree_status"
    printf 'Git branch: %s\n' "$branch_status"
}

main "$@"
