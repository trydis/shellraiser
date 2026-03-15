# Shellraiser

Shellraiser is a macOS terminal workspace app built with SwiftUI and GhosttyKit. It is designed for long-running agent sessions, with workspace switching, split panes, surface tabs, completion tracking, session persistence, macOS notifications, and AppleScript automation for driving terminal surfaces from scripts.

## Features

- Multi-workspace window layout with a dedicated sidebar and detail view
- Split-pane terminal composition with horizontal and vertical splits
- Surface tabs inside each pane for managing multiple sessions
- Command palette and keyboard shortcuts for workspace and pane actions
- Completion tracking and jump-to-next-completed-session workflow
- AppleScript support for creating workspaces, splitting terminals, focusing surfaces, sending keys, and inputting text
- macOS notifications — native notification when an agent turn completes in an unfocused surface; click to jump to it
- Git branch display — sidebar shows current branch name and a linked-worktree indicator per workspace
- Session resume — agent sessions (Claude Code, Codex) persist across app restarts
- Workspace persistence — full layout, pane tree, and surface state saved/restored automatically
- Pane zoom — toggle any split pane to fill the workspace area (Cmd+Shift+Return)
- Ghostty theming — terminal appearance driven by Ghostty config (background, foreground, opacity, blur, split divider color, unfocused split dimming)

## Requirements

- macOS 14 or newer
- Swift 5.9+
- Xcode 15 or newer
- Zig 0.15.2+ (required to build GhosttyKit from source)
- Git submodules initialized so the bundled `ghostty/` dependency is available

## Getting Started

Clone the repository and initialize submodules:

```bash
git clone https://github.com/trydis/shellraiser.git
cd shellraiser
git submodule update --init --recursive
```

Build the GhosttyKit xcframework (requires [Zig 0.15.2+](https://ziglang.org/download)):

```bash
cd ghostty
zig build -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=native -Doptimize=ReleaseFast
cd ..
```

Run the app locally:

```bash
make run
```

## Automation

Shellraiser exposes AppleScript objects and commands for workspaces, terminals, and surface configurations.

### Commands

| Command | Description |
|---|---|
| `new workspace` | Create a new workspace |
| `delete workspace` | Delete a workspace |
| `count workspaces` | Return the number of open workspaces |
| `new surface configuration` | Create a reusable surface configuration |
| `split` | Split a terminal in a given direction |
| `focus` | Focus a terminal surface |
| `input` | Input text into a terminal |
| `send` | Send a key sequence to a terminal |

The scripting definitions live under `Sources/Shellraiser/Infrastructure/AppleScript/`.
