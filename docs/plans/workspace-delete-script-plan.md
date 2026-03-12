# `workspace-delete.sh` Plan

## Summary

- Add a new `scripts/workspace-delete.sh` that takes the same workspace name input as the create scripts, derives the same slug/path, and removes:
  - the matching Shellraiser workspace
  - the linked Git worktree
  - the linked branch
- Default behavior: safe by default, interactive when destructive.
- Matching rule: fail if multiple Shellraiser workspaces match the same linked worktree path.

## Implementation Changes

- Extend `scripts/workspace-shellraiser-common.sh` with shared delete helpers:
  - resolve the canonical main worktree root from `git rev-parse --git-common-dir` so delete works even when invoked from a linked worktree
  - reuse existing slug/path derivation
  - resolve the registered worktree path for a branch and validate it matches the expected sibling path
  - prompt for yes/no confirmation in shell
  - inspect whether a worktree is clean before removal
- Add `scripts/workspace-delete.sh` with this flow:
  1. resolve workspace name, slug, canonical repo root, expected worktree path, branch name
  2. find the registered linked worktree for that branch; fail if branch/path do not match the expected workspace mapping
  3. query Shellraiser for a workspace whose stable root path equals the linked worktree path
  4. fail if multiple Shellraiser workspaces match
  5. if one matches, delete that Shellraiser workspace first so open terminals are released cleanly
  6. if the Git worktree is dirty, prompt before forcing `git worktree remove -f`; otherwise use plain `git worktree remove`
  7. try `git branch -d <branch>` after worktree removal; if Git refuses because the branch is unmerged, prompt before retrying with `git branch -D <branch>`
  8. print a compact summary of what was deleted vs skipped
- Behavior defaults:
  - no matching Shellraiser workspace: continue with Git cleanup and print a note
  - matching Shellraiser workspace not found because app is closed: continue with Git cleanup
  - current/main worktree can never be targeted for removal
  - dirty worktree prompt is interactive; non-interactive force mode is out of scope

## Public Interface Changes

- Add Shellraiser AppleScript support for deterministic workspace deletion:
  - new `delete workspace` command or equivalent direct scripting entrypoint that bypasses the UI confirmation sheet and calls `WorkspaceManager.deleteWorkspace(id:)`
  - new scriptable workspace property for stable matching, e.g. `root working directory`
- Add workspace-level persisted metadata if needed to make root-path matching stable:
  - preferred: explicit workspace root path on `WorkspaceModel`
  - fallback only if that is truly unnecessary: derive from initial surface config, not live terminal CWD
- `workspace-delete.sh` becomes the user-facing counterpart to the create scripts and uses the same name-to-slug/path convention.

## Test Plan

- Shell helper tests / smoke checks:
  - clean linked worktree deletes without prompts
  - dirty linked worktree prompts, cancel leaves everything intact, confirm forces removal
  - unmerged branch prompts before `-D`
  - branch/path mismatch fails without deleting anything
  - invocation from inside a linked worktree still resolves the canonical main repo correctly
- Shellraiser scripting tests:
  - workspace root path property is exposed and stable
  - scripted delete removes the requested workspace without requiring UI confirmation
  - duplicate matching workspaces cause the shell script to fail before deletion
- End-to-end manual scenario:
  - create workspace via existing launcher
  - run `workspace-delete.sh "<same name>"`
  - verify Shellraiser workspace is gone, linked worktree directory is gone, branch ref is gone

## Assumptions

- The delete script should be robust even if the user runs it from a linked worktree, not only from the main checkout.
- Workspace names are not unique; deletion targets the derived linked worktree path, not the visible name alone.
- Live terminal CWD is not reliable for matching because the app persists working-directory changes; use a stable workspace root property/metadata instead.
- Interactive prompts are acceptable for dirty worktrees and unmerged branch deletion.

## Unresolved Questions

- None.
