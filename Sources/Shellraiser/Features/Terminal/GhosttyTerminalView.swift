import AppKit
import Foundation
import SwiftUI
#if canImport(GhosttyKit)
import GhosttyKit
#endif

/// Host view contract used by terminal view syncing and tests.
@MainActor
protocol GhosttyTerminalHostView: GhosttyFocusableHost {
    func update(
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onUserInput: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    )
}

/// Runtime contract used by terminal host syncing and tests.
@MainActor
protocol GhosttyTerminalRuntimeControlling: AnyObject {
    func setSurfaceFocus(surfaceId: UUID, focused: Bool)
    func restorePendingFocusIfNeeded(surfaceId: UUID, hostView: any GhosttyFocusableHost)
}

/// Terminal panel view that embeds libghostty when available.
struct GhosttyTerminalView: NSViewRepresentable {
    let surface: SurfaceModel
    let config: TerminalPanelConfig
    let isFocused: Bool
    let onActivate: () -> Void
    let onIdleNotification: () -> Void
    let onUserInput: () -> Void
    let onTitleChange: (String) -> Void
    let onWorkingDirectoryChange: (String) -> Void
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
            onWorkingDirectoryChange: onWorkingDirectoryChange,
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
        guard let host = nsView as? (NSView & GhosttyTerminalHostView) else { return }
        Self.syncHostView(
            host,
            runtime: GhosttyRuntime.shared,
            surface: surface,
            config: config,
            isFocused: isFocused,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onUserInput: onUserInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        #endif
    }

    /// Detaches host views when SwiftUI unmounts this representable.
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        #if canImport(GhosttyKit)
        guard let host = nsView as? LibghosttySurfaceView else { return }
        GhosttyRuntime.shared.detachHost(surfaceId: host.surfaceId)
        #endif
    }

    /// Synchronizes an existing host view with current surface state and focus routing.
    static func syncHostView(
        _ host: any GhosttyTerminalHostView,
        runtime: any GhosttyTerminalRuntimeControlling,
        surface: SurfaceModel,
        config: TerminalPanelConfig,
        isFocused: Bool,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onUserInput: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) {
        host.update(
            surfaceModel: surface,
            terminalConfig: config,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onUserInput: onUserInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        runtime.setSurfaceFocus(surfaceId: surface.id, focused: isFocused)
        runtime.restorePendingFocusIfNeeded(surfaceId: surface.id, hostView: host)
    }
}

#if canImport(GhosttyKit)
extension LibghosttySurfaceView: GhosttyTerminalHostView {}
extension GhosttyRuntime: GhosttyTerminalRuntimeControlling {}
#endif
