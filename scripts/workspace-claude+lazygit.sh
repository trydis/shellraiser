#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workspace-shellraiser-common.sh
source "$script_dir/workspace-shellraiser-common.sh"

main() {
    local repo_root workspace_name worktree_root branch_name
    repo_root="$(resolve_repo_root)"
    workspace_name="$(resolve_workspace_name "$@")"
    IFS=$'\t' read -r worktree_root branch_name < <(prepare_workspace_worktree "$repo_root" "$workspace_name")
    [[ -n "$worktree_root" && -n "$branch_name" ]] || fail_with_message "Failed to resolve the workspace worktree."

    run_shellraiser_workspace_with_commands "$worktree_root" "$workspace_name" "claude" "lazygit"
}

main "$@"
