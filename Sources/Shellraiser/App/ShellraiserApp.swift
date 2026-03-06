import SwiftUI
import AppKit

/// App delegate that confirms before allowing the application to terminate.
final class ShellraiserAppDelegate: NSObject, NSApplicationDelegate {
    /// Intercepts standard app termination and requires explicit user confirmation.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit Shellraiser?"
        alert.informativeText = "All workspaces and terminal sessions will be closed."
        alert.addButton(withTitle: "Quit Shellraiser")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return switch alert.runModal() {
        case .alertFirstButtonReturn:
            .terminateNow
        default:
            .terminateCancel
        }
    }
}

/// Application entry point for the Shellraiser macOS app.
@main
struct ShellraiserApp: App {
    @NSApplicationDelegateAdaptor(ShellraiserAppDelegate.self) private var appDelegate
    @StateObject private var manager = WorkspaceManager()

    /// Disables native macOS window tabbing so the app's own pane tabs remain the only tab UI.
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            WorkspaceCommands(manager: manager)
        }
    }
}

/// Menu-bar commands and keyboard shortcuts for workspace, pane, and terminal actions.
struct WorkspaceCommands: Commands {
    @ObservedObject var manager: WorkspaceManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Workspace") {
                _ = manager.createWorkspace(name: "Workspace")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(after: .sidebar) {
            Button("Command Palette") {
                manager.toggleCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Workspace") {
            Button("New Workspace") {
                _ = manager.createWorkspace(name: "Workspace")
            }

            Divider()

            Button("Rename Active Workspace") {
                manager.requestRenameSelectedWorkspace()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(manager.selectedWorkspace == nil)

            Button("Delete Active Workspace") {
                manager.requestDeleteSelectedWorkspace()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(manager.selectedWorkspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Switch to Workspace \(number)") {
                    manager.selectWorkspace(atDisplayIndex: number)
                }
                .keyboardShortcut(Self.keyEquivalent(for: number), modifiers: [.command])
                .disabled(!manager.hasWorkspace(atDisplayIndex: number))
            }

            Divider()

            Button("Jump to Next Completed Session") {
                manager.jumpToNextCompletedSession()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!manager.hasPendingCompletions)
        }

        CommandMenu("Pane") {
            Button("New Surface") {
                _ = manager.performFocusedPaneCommand(.newSurface)
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.newSurface))

            Button("Split Horizontally") {
                _ = manager.performFocusedPaneCommand(.split(.horizontal))
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.split(.horizontal)))

            Button("Split Vertically") {
                _ = manager.performFocusedPaneCommand(.split(.vertical))
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.split(.vertical)))

            Divider()

            Button(manager.closeFocusedItemTitle) {
                _ = manager.performFocusedPaneCommand(.closeActiveItem)
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!manager.canPerformFocusedPaneCommand(.closeActiveItem))

            Divider()

            Button("Focus Left Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.left))
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.left)))

            Button("Focus Right Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.right))
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.right)))

            Button("Focus Up Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.up))
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.up)))

            Button("Focus Down Pane") {
                _ = manager.performFocusedPaneCommand(.focus(.down))
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!manager.canPerformFocusedPaneCommand(.focus(.down)))

            Divider()

            Button("Next Tab In Pane") {
                _ = manager.performFocusedPaneCommand(.nextSurface)
            }
            .keyboardShortcut(.tab, modifiers: [.control])
            .disabled(!manager.canPerformFocusedPaneCommand(.nextSurface))

            Button("Previous Tab In Pane") {
                _ = manager.performFocusedPaneCommand(.previousSurface)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.previousSurface))

            Divider()

            Button("Toggle Split Zoom") {
                _ = manager.performFocusedPaneCommand(.toggleZoom)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(!manager.canPerformFocusedPaneCommand(.toggleZoom))
        }

        CommandMenu("Terminal") {
            Button("Reset Terminal") {
                manager.performFocusedSurfaceBindingAction("reset")
            }
            .disabled(!manager.hasFocusedSurface)

            Divider()

            Button("Increase Font Size") {
                manager.performFocusedSurfaceBindingAction("increase_font_size:1")
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)

            Button("Decrease Font Size") {
                manager.performFocusedSurfaceBindingAction("decrease_font_size:1")
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)

            Button("Reset Font Size") {
                manager.performFocusedSurfaceBindingAction("reset_font_size")
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(!manager.hasFocusedSurface)
        }
    }

    /// Maps workspace indices to numeric key equivalents for shortcuts.
    private static func keyEquivalent(for number: Int) -> KeyEquivalent {
        switch number {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        case 4: return "4"
        case 5: return "5"
        case 6: return "6"
        case 7: return "7"
        case 8: return "8"
        case 9: return "9"
        default: return "0"
        }
    }
}
