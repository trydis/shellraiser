import AppKit
import Foundation
import SwiftUI
#if canImport(GhosttyKit)
import GhosttyKit
#endif

/// Terminal panel view that embeds libghostty when available.
struct GhosttyTerminalView: NSViewRepresentable {
    let surface: SurfaceModel
    let config: TerminalPanelConfig
    let isFocused: Bool
    let onActivate: () -> Void
    let onIdleNotification: () -> Void
    let onUserInput: () -> Void
    let onTitleChange: (String) -> Void
    let onChildExited: () -> Void
    let onPaneNavigationRequest: (PaneNodeModel.PaneFocusDirection) -> Void

    /// Builds the AppKit surface host.
    func makeNSView(context: Context) -> NSView {
        #if canImport(GhosttyKit)
        let hostView = GhosttyRuntime.shared.acquireHostView(
            surfaceModel: surface,
            terminalConfig: config,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onUserInput: onUserInput,
            onTitleChange: onTitleChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        GhosttyRuntime.shared.setSurfaceFocus(surfaceId: surface.id, focused: isFocused)
        return hostView
        #else
        let text = NSTextField(labelWithString: "GhosttyKit is not linked in this build.")
        text.textColor = .secondaryLabelColor
        return text
        #endif
    }

    /// Updates the host surface with latest model values.
    func updateNSView(_ nsView: NSView, context: Context) {
        #if canImport(GhosttyKit)
        guard let host = nsView as? LibghosttySurfaceView else { return }
        host.update(
            surfaceModel: surface,
            terminalConfig: config,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onUserInput: onUserInput,
            onTitleChange: onTitleChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        GhosttyRuntime.shared.setSurfaceFocus(surfaceId: surface.id, focused: isFocused)
        #endif
    }

    /// Detaches host views when SwiftUI unmounts this representable.
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        #if canImport(GhosttyKit)
        guard let host = nsView as? LibghosttySurfaceView else { return }
        GhosttyRuntime.shared.detachHost(surfaceId: host.surfaceId)
        #endif
    }
}
