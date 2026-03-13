#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workspace-shellraiser-common.sh
source "$script_dir/workspace-shellraiser-common.sh"

main() {
    local repo_root worktree_name worktree_root branch_name

    repo_root="$(resolve_repo_root)"
    worktree_name="$(resolve_worktree_name "$@")"
    IFS=$'\t' read -r worktree_root branch_name < <(prepare_workspace_worktree "$repo_root" "$worktree_name")
    [[ -n "$worktree_root" && -n "$branch_name" ]] || fail_with_message "Failed to resolve the worktree path."

    printf 'Worktree name: %s\n' "$worktree_name"
    printf 'Worktree path: %s\n' "$worktree_root"
    printf 'Branch: %s\n' "$branch_name"
}

main "$@"
