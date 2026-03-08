# Shellraiser

Shellraiser is a macOS terminal workspace app built with SwiftUI and GhosttyKit. It is designed for long-running agent sessions, with workspace switching, split panes, surface tabs, completion tracking, and AppleScript automation for driving terminal surfaces from scripts.

## Features

- Multi-workspace window layout with a dedicated sidebar and detail view
- Split-pane terminal composition with horizontal and vertical splits
- Surface tabs inside each pane for managing multiple sessions
- Command palette and keyboard shortcuts for workspace and pane actions
- Completion tracking and jump-to-next-completed-session workflow
- AppleScript support for creating workspaces, splitting terminals, focusing surfaces, sending keys, and inputting text

## Requirements

- macOS 14 or newer
- Swift 5.9+
- Xcode 15 or newer
- Git submodules initialized so the bundled `ghostty/` dependency is available

## Getting Started

Clone the repository and initialize submodules:

```bash
git clone https://github.com/trydis/shellraiser.git
cd shellraiser
git submodule update --init --recursive
```

Build the macOS app bundle with Xcode:

```bash
make build-app
```

Run the app locally:

```bash
make run
```

## Automation

Shellraiser exposes AppleScript objects and commands for workspaces, terminals, and surface configurations. The scripting bridge supports workflows such as:

- Creating workspaces
- Creating reusable surface configurations
- Splitting a terminal in a given direction
- Focusing a terminal
- Sending text or control keys to a terminal

The scripting definitions live under `Sources/Shellraiser/Infrastructure/AppleScript/`.
