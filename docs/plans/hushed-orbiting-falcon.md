# Agent HQ — Cross-Workspace Session Dashboard

Implements item **#2** of `docs/plans/codex-copilot-productivity-features.md` (Tier 1, Impact 5,
Effort M). Item #1 (status taxonomy) landed in `9a61af0` and is the hard prerequisite — its
`awaitingInputSurfaceIds` / `busySurfaceIds` state is what makes this dashboard meaningful.

## Problem

Shellraiser's sidebar lists **workspaces**, not **sessions**. Only the selected workspace's surfaces
are visible; inactive workspaces are deliberately unmounted for GPU reasons. At 16 concurrent
sessions the operator's model of "what are all my agents doing" lives entirely in their head.

Both reference apps independently built this exact screen (Copilot **Agents page**, Codex
**Activity view** `Cmd+Opt+U`). This adds Shellraiser's equivalent: one flat, sorted list of every
surface across every workspace, rendered **from model state only**, with a transcript-derived
summary so rows say *what* each agent is doing — not merely that it is busy.

## Approach

A `Cmd+Opt+U` overlay sheet reusing `CommandPaletteView`'s chrome (search field, arrow-key nav,
Enter-to-activate, ESC), backed by a new `AgentHQEntry` view-model assembled from already-published
`WorkspaceManager` state. A separate `SessionSummaryService` reads the last agent message per agent
family off the main actor. A menu-bar extra surfaces the awaiting-input count when backgrounded.

**Critical constraint** (from `memory-growth-gpu-iosurface.md`): Agent HQ must never mount terminal
views for preview rows. Every column is derived from `@Published` model state or a cached text
summary. No `GhosttyRuntime` surface is created, retained, or touched by this feature.

## Decisions (confirmed)

| Decision | Choice |
|---|---|
| Presentation | Overlay sheet on `Cmd+Opt+U`; standalone window deferred to a follow-on todo |
| Transcript summary | All three agents (Claude JSONL · Codex rollout · Copilot SQLite) |
| Summary refresh | On HQ open + per-surface refresh on activity events, debounced |
| Menu-bar extra | In scope |
| Multi-select | Out of scope (single-select; #3 broadcast adds selection later) |
| Row actions | Jump (Enter), Rename, Close, Dismiss pending completion |

## Verified on-disk formats

Confirmed by inspecting real files on this machine — all three parse to clean prose:

- **Claude Code** — `~/.claude/projects/<slug>/<uuid>.jsonl`, already persisted in
  `SurfaceModel.transcriptPath`. Scan backwards for the last `type == "assistant"` record; take the
  final `message.content[]` block of `type == "text"`. Interleaved non-message records exist
  (`mode`, `permission-mode`, `bridge-session`, `ai-title`, `last-prompt`, `file-history-snapshot`)
  and must be skipped. When the trailing block is `tool_use`, fall back to `"Running <name>…"`.
- **Codex** — `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<sessionId>.jsonl`. Take the last
  `type == "event_msg"` whose `payload.type == "task_complete"` and read `payload.last_agent_message`
  — a ready-made one-liner. Note some rollout files contain only `session_meta` (no summary yet).
- **Copilot** — `~/.copilot/session-store.db` (SQLite). `sessions(id, cwd, branch, summary, ...)`
  and `turns(session_id, turn_index, user_message, assistant_response, timestamp)`. Take
  `assistant_response` from the highest `turn_index`, falling back to `sessions.summary`.

Only Claude's `transcriptPath` is persisted today — `parsedSessionIdentity` in
`WorkspaceManager+Completions.swift` returns a transcript path for `.claudeCode` only. Codex and
Copilot therefore need resolution **by session id**, handled inside the summary service rather than
by changing the persisted model.

## Enablers already in the codebase

Nothing here needs a new subsystem beyond the summary reader:

- `WorkspaceManager` publishes `busySurfaceIds`, `awaitingInputSurfaceIds`, `progressBySurfaceId`,
  `gitStatesBySurfaceId`, `liveCodexSessionSurfaceIds`.
- `PaneNodeModel.allSurfaceIds()`, `.surface(id:)`, `.paneId(containing:)`, `.pendingSurfaceSnapshots()`.
- `pendingCompletionTargets()` FIFO and `focusCompletionSurface(_:)` — the exact jump-to path to reuse.
- `CommandPaletteView` / `CommandPaletteSheet` overlay chrome and `CommandPaletteRow` styling.
- Row actions map to existing APIs: `setSurfaceTitle(workspaceId:surfaceId:title:)`,
  `closeSurface(workspaceId:paneId:surfaceId:)`,
  `surfaceManager.clearPendingCompletion(...)` + `completionNotifications.removeNotifications(for:)`.
- `AppTheme`, `chromeCard()`, `AppBackdrop()`, `WorkspaceNameSheet` (rename sheet pattern).

## Sort order

`needsInput` → `ready` (pending completion) → `running` → `idle`. Within `ready`, preserve the
existing FIFO `pendingCompletionSequence` so Agent HQ and `Cmd+Shift+U` agree on ordering. Within
other buckets, sort by `lastActivity` descending. Rows group under a workspace header but the sort is
global — status must not be buried under workspace grouping.

## Todos

1. **`agent-hq-status-model`** — Add `SurfaceActivityStatus` (`idle`/`running`/`needsInput`/`ready`)
   as a derived read-only projection over existing manager state; do **not** add a stored property to
   `SurfaceModel` (avoids a persistence migration and a second source of truth).
2. **`agent-hq-entry-model`** — `AgentHQEntry` value type (workspace id/name, pane id, surface id,
   title, agent type, status, branch + worktree flag, progress, lastActivity, summary) plus
   `WorkspaceManager+AgentHQ.swift` building and sorting the flattened list.
3. **`agent-hq-summary-service`** — `Infrastructure/History/SessionSummaryService.swift` with a
   per-agent reader. Tail-read a bounded byte window from the end of JSONL files (transcripts reach
   many MB — never read whole files); open the Copilot DB read-only (`mode=ro`, WAL-aware) and never
   write to it. Actor-isolated off the main actor, results cached by surface id, single-flight per
   surface, truncated to one line for display.
4. **`agent-hq-overlay-view`** — `Features/AgentHQ/AgentHQOverlay.swift` + `AgentHQRow.swift`,
   presented as a sheet from `ContentView` mirroring `CommandPaletteSheet`. Fuzzy filter over
   workspace name, surface title, branch, agent name, and summary.
5. **`agent-hq-row-actions`** — Enter/click jumps (reuse `focusCompletionSurface`); context menu and
   key equivalents for Rename, Close, and Dismiss. Close must confirm when the surface is `running`.
6. **`agent-hq-shortcut-wiring`** — `Cmd+Opt+U` in `WorkspaceManager+Shortcuts.swift` and the
   Workspace menu, plus a command palette entry. **Conflict check:** `Cmd+Opt+←/→/↑/↓` is pane focus;
   the `modifiers.contains([.command, .option])` branch returns early only for arrow keycodes, so
   `u` falls through safely — but the current `guard hasCommand, !hasOption, !hasControl` must be
   handled before that guard rejects it.
7. **`agent-hq-summary-refresh`** — Refresh on overlay open for visible rows; refresh a single
   surface from `handleAgentActivityEvent` on `.started`/`.completed`/`.waitingForInput`, debounced
   per surface. Clear cache entries in the existing surface-teardown path alongside
   `clearGitBranch` / `clearProgressReport`.
8. **`agent-hq-menu-bar-extra`** — `NSStatusItem` showing the awaiting-input count (falling back to
   pending-completion count), clicking it activates the app and opens Agent HQ. Must tolerate the
   app running with no windows.
9. **`agent-hq-tests`** — Unit tests for entry construction and sort order across multiple
   workspaces, each summary parser against fixture files (including the `tool_use` fallback, the
   `session_meta`-only Codex rollout, and a missing/unreadable transcript), row-action delegation,
   and cache invalidation on surface close.
10. **`agent-hq-window`** *(follow-on, deferred)* — Standalone resizable window hosting the same row
    views for a second monitor. Deliberately deferred; the row view should be factored so the window
    is purely a second host.

## Notes & considerations

- **No terminal mounting.** Restated because it is the one way this feature could regress the app:
  every row renders from model state or cached text.
- **Derived, not stored, status.** Keeps `SurfaceModel` `Codable` back-compat untouched and avoids
  the stored-bool drift that item #1 was written to fix.
- **Read-only on foreign stores.** Copilot's `session-store.db` is owned by another live process;
  open read-only and treat failures as "no summary" rather than surfacing errors.
- **Degrade quietly.** A missing transcript, an unparsed rollout, or a session with no turns yet
  shows a blank summary — never an error row.
- **Ordering must agree with `Cmd+Shift+U`.** If Agent HQ and the FIFO jump disagree the operator
  loses trust in both.
- **Repo conventions:** `*Model` / `*Manager` / `*View` naming, `///` doc comments, `@MainActor` on
  UI state, 4-space indent. Validate with `swift test` and `make build-app`.
