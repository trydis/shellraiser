import SwiftUI

/// Sheet wrapper for the app-owned command palette.
struct CommandPaletteSheet: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        CommandPaletteView(
            items: manager.commandPaletteItems(),
            onDismiss: {
                manager.dismissCommandPalette()
            }
        )
        .frame(minWidth: 680, idealWidth: 760, maxWidth: 820)
        .presentationBackground(.clear)
    }
}

/// Searchable command palette for workspace, pane, and terminal actions.
struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    /// Palette items filtered by the current query.
    private var filteredItems: [CommandPaletteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { item in
            item.searchText.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    /// Currently selected palette item, if the result set is non-empty.
    private var selectedItem: CommandPaletteItem? {
        guard !filteredItems.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), filteredItems.count - 1)
        return filteredItems[index]
    }

    var body: some View {
        VStack(spacing: 18) {
            shortcutBridge

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.highlight)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command Palette")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.textPrimary)

                        TextField("Search commands, panes, tabs, or workspaces", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .focused($isSearchFieldFocused)
                    }

                    Spacer()

                    Text("ESC")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .padding(20)

                Divider()
                    .overlay(AppTheme.stroke)

                if filteredItems.isEmpty {
                    ContentUnavailableView("No Matching Commands", systemImage: "magnifyingglass")
                        .frame(minHeight: 260)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    CommandPaletteRow(
                                        item: item,
                                        isSelected: selectedItem?.id == item.id,
                                        onActivate: {
                                            activate(item)
                                        }
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(14)
                        }
                        .frame(minHeight: 300, maxHeight: 460)
                        .onChange(of: selectedIndex) {
                            guard filteredItems.indices.contains(selectedIndex) else { return }
                            proxy.scrollTo(filteredItems[selectedIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .chromeCard()
        }
        .padding(20)
        .background {
            AppBackdrop()
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onExitCommand {
            onDismiss()
        }
    }

    /// Hidden shortcut handlers for command palette navigation.
    private var shortcutBridge: some View {
        Group {
            Button("") {
                moveSelection(by: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)

            Button("") {
                moveSelection(by: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)

            Button("") {
                if let selectedItem {
                    activate(selectedItem)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)
        }
        .frame(width: 0, height: 0)
    }

    /// Moves list selection while clamping to valid palette rows.
    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let nextIndex = min(max(selectedIndex + offset, 0), filteredItems.count - 1)
        selectedIndex = nextIndex
    }

    /// Executes the selected command and dismisses the palette.
    private func activate(_ item: CommandPaletteItem) {
        guard item.isEnabled else { return }
        onDismiss()
        item.action()
    }
}

/// Row chrome for a command palette result item.
struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 14) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isEnabled ? AppTheme.highlight : AppTheme.textSecondary.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.category)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if let shortcut = item.shortcut {
                    Text(shortcut.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.highlight.opacity(0.3) : AppTheme.stroke.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
    }
}
