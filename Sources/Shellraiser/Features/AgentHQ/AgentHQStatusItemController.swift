import AppKit
import Combine

/// Manages the menu-bar status item showing the current awaiting-input (or pending-completion)
/// count, so operators can see queued work at a glance without switching apps.
///
/// Owns its `NSStatusItem` independently of any window — safe to construct and click even before
/// the main window has appeared or after every window has been closed.
@MainActor
final class AgentHQStatusItemController {
    private let statusItem: NSStatusItem
    private weak var manager: WorkspaceManager?
    private var cancellable: AnyCancellable?

    /// Creates the status item and begins observing manager state for count updates.
    init(manager: WorkspaceManager) {
        self.manager = manager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.stack.badge.person.crop",
                accessibilityDescription: "Agent HQ"
            )
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick)
        }

        cancellable = manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
        updateStatusItem()
    }

    /// Activates the app, brings a window forward if one exists, and presents Agent HQ.
    @objc private func handleClick() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
        manager?.presentAgentHQ()
    }

    /// Recomputes the displayed count: awaiting-input takes priority, falling back to pending completions.
    private func updateStatusItem() {
        guard let manager, let button = statusItem.button else { return }

        let awaitingCount = manager.awaitingInputSurfaceIds.count
        let count = awaitingCount > 0 ? awaitingCount : manager.pendingCompletionTargets().count
        button.title = count > 0 ? " \(count)" : ""
    }
}
