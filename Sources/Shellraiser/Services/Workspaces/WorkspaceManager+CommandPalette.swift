import Foundation

/// Command palette item generation for the shared workspace manager.
extension WorkspaceManager {
    /// Toggles presentation of the app-owned command palette.
    func toggleCommandPalette() {
        isCommandPalettePresented.toggle()
    }

    /// Dismisses the app-owned command palette if it is open.
    func dismissCommandPalette() {
        isCommandPalettePresented = false
    }

    /// Builds the current list of searchable command palette items.
    func commandPaletteItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        items.append(
            CommandPaletteItem(
                id: "workspace.new",
                title: "New Workspace",
                category: "Workspace",
                systemImage: "square.stack.badge.plus",
                shortcut: "cmd-n",
                isEnabled: true,
                keywords: ["create", "window", "workspace"]
            ) {
                _ = self.createWorkspace(name: "Workspace")
            }
        )

        items.append(
            CommandPaletteItem(
                id: "workspace.rename",
                title: "Rename Active Workspace",
                category: "Workspace",
                systemImage: "pencil",
                shortcut: "cmd-shift-r",
                isEnabled: selectedWorkspace != nil,
                keywords: ["rename", "workspace", "label"]
            ) {
                self.requestRenameSelectedWorkspace()
            }
        )

        for (index, workspace) in workspaces.enumerated() where index < 9 {
            items.append(
                CommandPaletteItem(
                    id: "workspace.switch.\(workspace.id.uuidString)",
                    title: "Switch to Workspace \(index + 1): \(workspace.name)",
                    category: "Workspace",
                    systemImage: "rectangle.stack",
                    shortcut: "cmd-\(index + 1)",
                    isEnabled: true,
                    keywords: ["select", "open", workspace.name]
                ) {
                    self.selectWorkspace(workspace.id)
                }
            )
        }

        items.append(
            CommandPaletteItem(
                id: "workspace.next-completion",
                title: "Jump To Next Completed Session",
                category: "Workspace",
                systemImage: "bell.badge",
                shortcut: "cmd-shift-u",
                isEnabled: hasPendingCompletions,
                keywords: ["notification", "completion", "alert", "queue", "next"]
            ) {
                self.jumpToNextCompletedSession()
            }
        )

        items.append(contentsOf: paneCommandPaletteItems())
        items.append(contentsOf: terminalCommandPaletteItems())

        return items
    }

    /// Builds command palette items for app-owned pane commands.
    private func paneCommandPaletteItems() -> [CommandPaletteItem] {
        let commands: [(id: String, title: String, category: String, image: String, shortcut: String?, keywords: [String], command: FocusedPaneCommand)] = [
            ("pane.new-surface", "New Surface", "Pane", "plus", "cmd-t", ["tab", "terminal", "surface"], .newSurface),
            ("pane.split-horizontal", "Split Horizontally", "Pane", "rectangle.split.2x1", "cmd-d", ["pane", "split", "horizontal"], .split(.horizontal)),
            ("pane.split-vertical", "Split Vertically", "Pane", "rectangle.split.1x2", "cmd-shift-d", ["pane", "split", "vertical"], .split(.vertical)),
            ("pane.close", closeFocusedItemTitle, "Pane", "xmark", "cmd-w", ["close", "pane", "tab"], .closeActiveItem),
            ("pane.focus-left", "Focus Left Pane", "Pane", "arrow.left", "cmd-opt-left", ["pane", "left", "focus"], .focus(.left)),
            ("pane.focus-right", "Focus Right Pane", "Pane", "arrow.right", "cmd-opt-right", ["pane", "right", "focus"], .focus(.right)),
            ("pane.focus-up", "Focus Up Pane", "Pane", "arrow.up", "cmd-opt-up", ["pane", "up", "focus"], .focus(.up)),
            ("pane.focus-down", "Focus Down Pane", "Pane", "arrow.down", "cmd-opt-down", ["pane", "down", "focus"], .focus(.down)),
            ("pane.next-tab", "Next Tab In Pane", "Pane", "chevron.right", "ctrl-tab", ["tab", "next", "surface"], .nextSurface),
            ("pane.previous-tab", "Previous Tab In Pane", "Pane", "chevron.left", "ctrl-shift-tab", ["tab", "previous", "surface"], .previousSurface),
            ("pane.toggle-zoom", "Toggle Split Zoom", "Pane", "arrow.up.left.and.arrow.down.right", "cmd-shift-return", ["zoom", "pane", "split"], .toggleZoom)
        ]

        return commands.map { item in
            CommandPaletteItem(
                id: item.id,
                title: item.title,
                category: item.category,
                systemImage: item.image,
                shortcut: item.shortcut,
                isEnabled: canPerformFocusedPaneCommand(item.command),
                keywords: item.keywords
            ) {
                _ = self.performFocusedPaneCommand(item.command)
            }
        }
    }

    /// Builds command palette items for terminal-local Ghostty actions.
    private func terminalCommandPaletteItems() -> [CommandPaletteItem] {
        let commands: [(id: String, title: String, image: String, shortcut: String?, keywords: [String], action: String)] = [
            ("terminal.find", "Find in Terminal", "magnifyingglass", "cmd-f", ["find", "search", "text", "grep"], "start_search"),
            ("terminal.reset", "Reset Terminal", "arrow.clockwise", nil, ["terminal", "surface", "reset"], "reset"),
            ("terminal.font-increase", "Increase Font Size", "plus.magnifyingglass", "cmd-=", ["font", "text", "zoom", "increase"], "increase_font_size:1"),
            ("terminal.font-decrease", "Decrease Font Size", "minus.magnifyingglass", "cmd--", ["font", "text", "zoom", "decrease"], "decrease_font_size:1"),
            ("terminal.font-reset", "Reset Font Size", "textformat.size", "cmd-0", ["font", "text", "zoom", "reset"], "reset_font_size")
        ]

        return commands.map { item in
            CommandPaletteItem(
                id: item.id,
                title: item.title,
                category: "Terminal",
                systemImage: item.image,
                shortcut: item.shortcut,
                isEnabled: hasFocusedSurface,
                keywords: item.keywords
            ) {
                _ = self.performFocusedSurfaceBindingAction(item.action)
            }
        }
    }
}
