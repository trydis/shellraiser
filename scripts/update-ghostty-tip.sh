#!/usr/bin/env bash

set -euo pipefail

SUBMODULE_PATH="ghostty"
TAG_NAME="tip"
COMMIT_MESSAGE="Update ghostty submodule to tip"

main() {
    local repo_root
    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"

    ensure_clean_superproject
    ensure_submodule_exists
    ensure_submodule_initialized

    git -C "$SUBMODULE_PATH" fetch --tags

    local target_commit current_commit
    target_commit="$(git -C "$SUBMODULE_PATH" rev-list -n 1 "refs/tags/$TAG_NAME")"
    if [[ -z "$target_commit" ]]; then
        echo "Tag '$TAG_NAME' was not found in $SUBMODULE_PATH." >&2
        exit 1
    fi

    current_commit="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"
    if [[ "$current_commit" == "$target_commit" ]]; then
        echo "$SUBMODULE_PATH is already at tag '$TAG_NAME' ($target_commit)."
        exit 0
    fi

    git -C "$SUBMODULE_PATH" checkout --detach "$target_commit"

    git add "$SUBMODULE_PATH"

    if git diff --cached --quiet -- "$SUBMODULE_PATH"; then
        echo "No submodule pointer change detected after updating $SUBMODULE_PATH."
        exit 0
    fi

    git commit -m "$COMMIT_MESSAGE"

    echo "Updated $SUBMODULE_PATH to '$TAG_NAME' ($target_commit) and committed the pointer change."
}

ensure_clean_superproject() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Superproject has uncommitted changes. Commit or stash them before updating $SUBMODULE_PATH." >&2
        exit 1
    fi
}

ensure_submodule_exists() {
    if [[ ! -d "$SUBMODULE_PATH" ]]; then
        echo "Submodule path '$SUBMODULE_PATH' does not exist." >&2
        exit 1
    fi
}

ensure_submodule_initialized() {
    if ! git -C "$SUBMODULE_PATH" rev-parse --git-dir >/dev/null 2>&1; then
        git submodule update --init "$SUBMODULE_PATH"
    fi
}

main "$@"
