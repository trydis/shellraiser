#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=workspace-shellraiser-common.sh
source "$script_dir/workspace-shellraiser-common.sh"

main() {
    local repo_root workspace_name
    repo_root="$(resolve_repo_root)"
    workspace_name="$(resolve_workspace_name "$@")"

    run_shellraiser_workspace_with_commands "$repo_root" "$workspace_name" "co" "lg"
}

main "$@"
