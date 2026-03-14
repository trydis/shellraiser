#!/usr/bin/env bash

if [[ -n "${BASH_VERSION:-}" ]]; then
    shellraiser_script_path="${BASH_SOURCE[0]}"
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        shellraiser_script_sourced="1"
    else
        shellraiser_script_sourced="0"
    fi
else
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        shellraiser_script_path="${(%):-%x}"
    else
        shellraiser_script_path="$0"
    fi

    if [[ -n "${ZSH_VERSION:-}" && "${ZSH_EVAL_CONTEXT:-}" == *:file ]]; then
        shellraiser_script_sourced="1"
    else
        shellraiser_script_sourced="0"
    fi
fi

if [[ "$shellraiser_script_sourced" != "1" ]]; then
    set -euo pipefail
fi

SHELLRAISER_SCRIPT_SOURCED="$shellraiser_script_sourced"
script_dir="$(cd "$(dirname "$shellraiser_script_path")" && pwd)"
# shellcheck source=workspace-shellraiser-common.sh
source "$script_dir/workspace-shellraiser-common.sh"

# Changes into the prepared worktree for sourced usage or launches an interactive shell there.
enter_prepared_worktree() {
    local worktree_root="$1"
    local interactive_shell="${SHELL:-/bin/bash}"

    if [[ ! -x "$interactive_shell" ]]; then
        interactive_shell="/bin/bash"
    fi

    cd "$worktree_root" || fail_with_message "Failed to switch into worktree '$worktree_root'."

    if [[ "${SHELLRAISER_SCRIPT_SOURCED:-0}" == "1" ]]; then
        return 0
    fi

    if [[ -t 0 && -t 1 ]]; then
        exec "$interactive_shell" -i
    fi
}

# Creates or reuses a Git worktree and enters it when running interactively.
main() {
    local repo_root worktree_name worktree_root branch_name worktree_status

    repo_root="$(resolve_repo_root)"
    worktree_name="$(resolve_worktree_name "$@")"
    IFS=$'\t' read -r worktree_root branch_name worktree_status < <(
        prepare_workspace_worktree_with_status "$repo_root" "$worktree_name"
    )
    [[ -n "$worktree_root" && -n "$branch_name" && -n "$worktree_status" ]] \
        || fail_with_message "Failed to resolve the worktree path."

    if [[ "$worktree_status" == "created" ]]; then
        bootstrap_ghostty_for_worktree "$worktree_root" || return 1
    fi

    printf 'Worktree name: %s\n' "$worktree_name"
    printf 'Worktree path: %s\n' "$worktree_root"
    printf 'Branch: %s\n' "$branch_name"

    enter_prepared_worktree "$worktree_root" || return 1
}

main "$@"
