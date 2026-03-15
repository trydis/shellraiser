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
        onInput: @escaping (SurfaceInputEvent) -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    )
}

/// Runtime contract used by terminal host syncing and tests.
@MainActor
protocol GhosttyTerminalRuntimeControlling: AnyObject {
    func attachHost(surfaceId: UUID)
    func detachHost(surfaceId: UUID)
    func setSurfaceFocus(surfaceId: UUID, focused: Bool)
    func restorePendingFocusIfNeeded(surfaceId: UUID, hostView: any GhosttyFocusableHost)
}

/// Wrapper AppKit view that gives each SwiftUI mount its own root `NSView`.
@MainActor
final class GhosttyTerminalContainerView: NSView {
    private(set) var mountedSurfaceId: UUID?

    /// Creates an empty container ready to host a shared terminal surface view.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Mounts the shared host view into this container and sizes it to fill the pane.
    func mountHostView(_ hostView: NSView, surfaceId: UUID) {
        subviews
            .filter { $0 !== hostView }
            .forEach { $0.removeFromSuperview() }

        if hostView.superview !== self {
            hostView.removeFromSuperview()
            addSubview(hostView)
        }

        hostView.frame = bounds
        hostView.autoresizingMask = [.width, .height]
        mountedSurfaceId = surfaceId
    }

    /// Clears the mounted surface tracking during teardown.
    func clearMountedSurface() {
        mountedSurfaceId = nil
    }
}

/// Terminal panel view that embeds libghostty when available.
struct GhosttyTerminalView: NSViewRepresentable {
    let surface: SurfaceModel
    let config: TerminalPanelConfig
    let isFocused: Bool
    let onActivate: () -> Void
    let onIdleNotification: () -> Void
    let onInput: (SurfaceInputEvent) -> Void
    let onTitleChange: (String) -> Void
    let onWorkingDirectoryChange: (String) -> Void
    let onChildExited: () -> Void
    let onPaneNavigationRequest: (PaneNodeModel.PaneFocusDirection) -> Void
    let onSearchStateChange: (SurfaceSearchState?) -> Void

    /// Builds the AppKit surface host.
    func makeNSView(context: Context) -> NSView {
        #if canImport(GhosttyKit)
        let containerView = GhosttyTerminalContainerView(frame: .zero)
        let hostView = GhosttyRuntime.shared.acquireHostView(
            surfaceModel: surface,
            terminalConfig: config,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onInput: onInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest,
            onSearchStateChange: onSearchStateChange
        )
        Self.syncContainerView(
            containerView,
            host: hostView,
            runtime: GhosttyRuntime.shared,
            surface: surface,
            config: config,
            isFocused: isFocused,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onInput: onInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        return containerView
        #else
        let text = NSTextField(labelWithString: "GhosttyKit is not linked in this build.")
        text.textColor = .secondaryLabelColor
        return text
        #endif
    }

    /// Updates the host surface with latest model values.
    func updateNSView(_ nsView: NSView, context: Context) {
        #if canImport(GhosttyKit)
        guard let container = nsView as? GhosttyTerminalContainerView else { return }
        let host = GhosttyRuntime.shared.acquireHostView(
            surfaceModel: surface,
            terminalConfig: config,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onInput: onInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest,
            onSearchStateChange: onSearchStateChange
        )
        Self.syncContainerView(
            container,
            host: host,
            runtime: GhosttyRuntime.shared,
            surface: surface,
            config: config,
            isFocused: isFocused,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onInput: onInput,
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
        guard let container = nsView as? GhosttyTerminalContainerView else { return }
        Self.dismantleContainerView(container, runtime: GhosttyRuntime.shared)
        #endif
    }

    /// Synchronizes a per-mount wrapper with the shared host view cached by the runtime.
    static func syncContainerView(
        _ container: GhosttyTerminalContainerView,
        host: NSView & GhosttyTerminalHostView,
        runtime: any GhosttyTerminalRuntimeControlling,
        surface: SurfaceModel,
        config: TerminalPanelConfig,
        isFocused: Bool,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onInput: @escaping (SurfaceInputEvent) -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) {
        if container.mountedSurfaceId != surface.id {
            if let mountedSurfaceId = container.mountedSurfaceId {
                runtime.detachHost(surfaceId: mountedSurfaceId)
            }
            runtime.attachHost(surfaceId: surface.id)
        }

        container.mountHostView(host, surfaceId: surface.id)
        syncHostView(
            host,
            runtime: runtime,
            surface: surface,
            config: config,
            isFocused: isFocused,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onInput: onInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
    }

    /// Detaches the mounted surface tracked by a wrapper container during teardown.
    static func dismantleContainerView(
        _ container: GhosttyTerminalContainerView,
        runtime: any GhosttyTerminalRuntimeControlling
    ) {
        guard let surfaceId = container.mountedSurfaceId else { return }
        runtime.detachHost(surfaceId: surfaceId)
        container.clearMountedSurface()
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
        onInput: @escaping (SurfaceInputEvent) -> Void,
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
            onInput: onInput,
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
