import AppKit

/// Keyboard shortcut routing for the shared workspace manager.
extension WorkspaceManager {
    /// Registers a local key monitor so shortcuts also work while terminal views are focused.
    func registerLocalShortcutMonitor() {
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalShortcut(event) ? nil : event
        }
    }

    /// Handles app-level keyboard shortcuts and consumes handled events.
    func handleLocalShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)

        if hasControl, !hasCommand, !hasOption, event.keyCode == 48 {
            return performFocusedPaneCommand(hasShift ? .previousSurface : .nextSurface)
        }

        if modifiers.contains([.command, .option]) {
            let handleDirection: (PaneNodeModel.PaneFocusDirection) -> Bool = { direction in
                self.performFocusedPaneCommand(.focus(direction))
            }

            if let specialKey = event.specialKey {
                switch specialKey {
                case .leftArrow:
                    return handleDirection(.left)
                case .rightArrow:
                    return handleDirection(.right)
                case .downArrow:
                    return handleDirection(.down)
                case .upArrow:
                    return handleDirection(.up)
                default:
                    break
                }
            }

            switch event.keyCode {
            case 123:
                return handleDirection(.left)
            case 124:
                return handleDirection(.right)
            case 125:
                return handleDirection(.down)
            case 126:
                return handleDirection(.up)
            default:
                break
            }
        }

        if hasCommand, !hasOption, !hasControl, !hasShift {
            switch event.keyCode {
            case 126:
                selectPreviousWorkspace()
                return true
            case 125:
                selectNextWorkspace()
                return true
            default:
                break
            }
        }

        guard hasCommand, !hasOption, !hasControl else { return false }

        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            return false
        }

        if key == "n", !hasShift {
            _ = createWorkspace(name: "Workspace")
            return true
        }

        if key == "p", hasShift {
            toggleCommandPalette()
            return true
        }

        if key == "u", hasShift {
            jumpToNextCompletedSession()
            return true
        }

        if key == "w", hasShift {
            requestDeleteSelectedWorkspace()
            return true
        }

        if key == "r", hasShift {
            requestRenameSelectedWorkspace()
            return true
        }

        if !hasSelectedWorkspace {
            if !hasShift, let index = Int(key), (1...9).contains(index) {
                selectWorkspace(atDisplayIndex: index)
                return true
            }
            return false
        }

        if key == "t", !hasShift {
            return performFocusedPaneCommand(.newSurface)
        }

        if key == "f", !hasShift {
            return performFocusedSurfaceBindingAction("start_search")
        }

        if !hasShift, let index = Int(key), (1...9).contains(index) {
            selectWorkspace(atDisplayIndex: index)
            return true
        }

        if key == "d" {
            return performFocusedPaneCommand(.split(hasShift ? .vertical : .horizontal))
        }

        if key == "w", !hasShift {
            return performFocusedPaneCommand(.closeActiveItem)
        }

        if hasShift && (event.keyCode == 36 || event.keyCode == 76) {
            return performFocusedPaneCommand(.toggleZoom)
        }

        return false
    }
}
