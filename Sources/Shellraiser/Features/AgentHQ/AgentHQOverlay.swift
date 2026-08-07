import SwiftUI

/// Sheet wrapper for the Agent HQ cross-workspace session dashboard.
struct AgentHQSheet: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        AgentHQOverlay(
            entries: manager.agentHQEntries(),
            onSelect: { entry in
                manager.focusCompletionSurface(entry.surfaceId)
                manager.dismissAgentHQ()
            },
            onDismiss: {
                manager.dismissAgentHQ()
            }
        )
        .frame(minWidth: 760, idealWidth: 860, maxWidth: 960)
        .presentationBackground(.clear)
    }
}

/// Searchable, keyboard-navigable list of every live surface across all workspaces.
///
/// Rendered entirely from `AgentHQEntry` snapshots — never mounts a terminal view. See
/// `docs/plans/memory-growth-gpu-iosurface.md` for why that constraint matters at 15+ sessions.
struct AgentHQOverlay: View {
    let entries: [AgentHQEntry]
    let onSelect: (AgentHQEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    /// Entries filtered by the current query across workspace, title, branch, agent, and summary text.
    private var filteredEntries: [AgentHQEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter { entry in
            entry.searchText.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    /// Currently selected row, if the result set is non-empty.
    private var selectedEntry: AgentHQEntry? {
        guard !filteredEntries.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), filteredEntries.count - 1)
        return filteredEntries[index]
    }

    var body: some View {
        VStack(spacing: 18) {
            shortcutBridge

            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(AppTheme.stroke)

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        entries.isEmpty ? "No Active Sessions" : "No Matching Sessions",
                        systemImage: "rectangle.stack.badge.person.crop"
                    )
                    .frame(minHeight: 260)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                    AgentHQRow(
                                        entry: entry,
                                        isSelected: selectedEntry?.id == entry.id,
                                        onActivate: {
                                            onSelect(entry)
                                        }
                                    )
                                    .id(entry.id)
                                }
                            }
                            .padding(14)
                        }
                        .frame(minHeight: 320, maxHeight: 520)
                        .onChange(of: selectedIndex) {
                            guard filteredEntries.indices.contains(selectedIndex) else { return }
                            proxy.scrollTo(filteredEntries[selectedIndex].id, anchor: .center)
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

    /// Header row with title, search field, and result count.
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.highlight)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent HQ")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(AppTheme.textPrimary)

                TextField("Search sessions, branches, or workspaces", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .focused($isSearchFieldFocused)
            }

            Spacer()

            Text("\(filteredEntries.count) SESSION\(filteredEntries.count == 1 ? "" : "S")")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.06)))

            Text("ESC")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(20)
    }

    /// Hidden shortcut handlers for list navigation.
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
                if let selectedEntry {
                    onSelect(selectedEntry)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)
        }
        .frame(width: 0, height: 0)
    }

    /// Moves list selection while clamping to valid rows.
    private func moveSelection(by offset: Int) {
        guard !filteredEntries.isEmpty else { return }
        let nextIndex = min(max(selectedIndex + offset, 0), filteredEntries.count - 1)
        selectedIndex = nextIndex
    }
}

private extension AgentHQEntry {
    /// Combined searchable text used by Agent HQ filtering.
    var searchText: String {
        [workspaceName, title, agentType.displayName, branchName ?? "", summary ?? ""]
            .joined(separator: " ")
    }
}
