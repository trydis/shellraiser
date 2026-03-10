import AppKit
import Foundation
#if canImport(GhosttyKit)
import GhosttyKit

/// Minimal focus-host contract used by runtime focus restoration and tests.
@MainActor
protocol GhosttyFocusableHost: AnyObject {
    var hostWindow: NSWindow? { get }
    var firstResponderTarget: NSResponder { get }
}

/// Minimal global runtime that owns libghostty app/config and surface registration.
@MainActor
final class GhosttyRuntime {
    /// Notification posted when Ghostty-driven appearance inputs change.
    static let appearanceDidChangeNotification = Notification.Name(
        "GhosttyRuntime.appearanceDidChange"
    )

    /// Main-thread-safe snapshot of libghostty actions we care about.
    enum SurfaceActionEvent {
        case idleNotification
        case title(String)
        case workingDirectory(String)
        case childExited
    }

    struct SurfaceCallbacks {
        let onIdleNotification: () -> Void
        let onTitleChange: (String) -> Void
        let onWorkingDirectoryChange: (String) -> Void
        let onChildExited: () -> Void
    }

    /// Pasteboard targets supported by the embedded host.
    enum ClipboardTarget {
        case standard
        case selection
    }

    /// Decoded clipboard payload item imported from libghostty.
    struct ClipboardContent {
        let mime: String
        let data: String

        /// Converts a C clipboard payload into a Swift value when both fields are valid UTF-8.
        static func from(content: ghostty_clipboard_content_s) -> ClipboardContent? {
            guard let mimePointer = content.mime,
                  let dataPointer = content.data else {
                return nil
            }

            return ClipboardContent(
                mime: String(cString: mimePointer),
                data: String(cString: dataPointer)
            )
        }
    }

    /// Visual styling used to dim unfocused split panes.
    struct UnfocusedSplitStyle {
        let overlayOpacity: Double
        let fillColor: NSColor
    }

    /// Visual styling for app-managed pane chrome sourced from Ghostty config.
    struct ChromeStyle {
        let backgroundColor: NSColor
        let foregroundColor: NSColor
        let backgroundOpacity: Double
        let backgroundOpacityCells: Bool
        let backgroundBlurRadius: Int
        let splitDividerColor: NSColor
    }

    static let shared = GhosttyRuntime()

    private var initialized = false
    private var app: ghostty_app_t?
    private var config: ghostty_config_t?

    private var surfaceHandlesById: [UUID: ghostty_surface_t] = [:]
    private var surfaceIdsByHandle: [UInt: UUID] = [:]
    private var callbacksBySurfaceId: [UUID: SurfaceCallbacks] = [:]
    private var hostViewsBySurfaceId: [UUID: LibghosttySurfaceView] = [:]
    private var mountedHostCountsBySurfaceId: [UUID: Int] = [:]
    private var releasedSurfaceIds: Set<UUID> = []
    private var pendingFocusedSurfaceId: UUID?

    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?

    /// Registers callbacks for a surface model identifier.
    func registerSurfaceCallbacks(
        surfaceId: UUID,
        onIdleNotification: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void
    ) {
        callbacksBySurfaceId[surfaceId] = SurfaceCallbacks(
            onIdleNotification: onIdleNotification,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited
        )
    }

    /// Returns an existing host for a surface id or creates one on demand.
    func acquireHostView(
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onUserInput: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) -> LibghosttySurfaceView {
        registerSurfaceCallbacks(
            surfaceId: surfaceModel.id,
            onIdleNotification: onIdleNotification,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited
        )
        releasedSurfaceIds.remove(surfaceModel.id)

        if let existing = hostViewsBySurfaceId[surfaceModel.id] {
            existing.update(
                surfaceModel: surfaceModel,
                terminalConfig: terminalConfig,
                onActivate: onActivate,
                onIdleNotification: onIdleNotification,
                onUserInput: onUserInput,
                onTitleChange: onTitleChange,
                onWorkingDirectoryChange: onWorkingDirectoryChange,
                onChildExited: onChildExited,
                onPaneNavigationRequest: onPaneNavigationRequest
            )
            return existing
        }

        let created = LibghosttySurfaceView(
            surfaceModel: surfaceModel,
            terminalConfig: terminalConfig,
            onActivate: onActivate,
            onIdleNotification: onIdleNotification,
            onUserInput: onUserInput,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited,
            onPaneNavigationRequest: onPaneNavigationRequest
        )
        hostViewsBySurfaceId[surfaceModel.id] = created
        mountedHostCountsBySurfaceId[surfaceModel.id] = 0
        return created
    }

    /// Marks a shared host view as mounted into one SwiftUI-owned wrapper container.
    func attachHost(surfaceId: UUID) {
        mountedHostCountsBySurfaceId[surfaceId, default: 0] += 1
    }

    /// Marks a host view as detached and schedules delayed cleanup.
    func detachHost(surfaceId: UUID) {
        let current = mountedHostCountsBySurfaceId[surfaceId, default: 0]
        let next = max(0, current - 1)
        mountedHostCountsBySurfaceId[surfaceId] = next
        guard next == 0, releasedSurfaceIds.contains(surfaceId) else { return }
        cleanupReleasedSurface(surfaceId: surfaceId)
    }

    /// Releases a surface that was removed from workspace state.
    func releaseSurface(surfaceId: UUID) {
        releasedSurfaceIds.insert(surfaceId)
        guard mountedHostCountsBySurfaceId[surfaceId, default: 0] == 0 else { return }
        cleanupReleasedSurface(surfaceId: surfaceId)
    }

    /// Finalizes destruction for a released surface once no host view remains mounted.
    private func cleanupReleasedSurface(surfaceId: UUID) {
        guard releasedSurfaceIds.contains(surfaceId) else { return }

        releasedSurfaceIds.remove(surfaceId)
        callbacksBySurfaceId.removeValue(forKey: surfaceId)
        mountedHostCountsBySurfaceId.removeValue(forKey: surfaceId)

        if let host = hostViewsBySurfaceId.removeValue(forKey: surfaceId) {
            host.shutdown()
            return
        }

        if let surface = surfaceHandlesById[surfaceId] {
            destroySurface(handle: surface)
        }
    }

    /// Creates a new libghostty surface associated with an AppKit host view.
    func createSurface(
        for view: LibghosttySurfaceView,
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig
    ) -> ghostty_surface_t? {
        initializeIfNeeded()
        guard let app else { return nil }

        let workingDirectory = Self.effectiveWorkingDirectory(from: terminalConfig.workingDirectory)
        let command = Self.launchCommand(
            shell: terminalConfig.shell,
            workingDirectory: workingDirectory
        )
        let environment = mergedEnvironment(
            for: terminalConfig,
            surfaceId: surfaceModel.id
        )

        let created: ghostty_surface_t? = withSurfaceConfig(
            view: view,
            workingDirectory: workingDirectory,
            command: command,
            environment: environment
        ) { config in
            ghostty_surface_new(app, &config)
        }

        guard let created else { return nil }

        surfaceHandlesById[surfaceModel.id] = created
        surfaceIdsByHandle[surfaceKey(created)] = surfaceModel.id
        return created
    }

    /// Destroys a libghostty surface by handle.
    ///
    /// Using the handle avoids a race where an old view deinit could destroy a newly
    /// recreated surface that reused the same model identifier.
    func destroySurface(handle: ghostty_surface_t) {
        let key = surfaceKey(handle)
        let surfaceId = surfaceIdsByHandle.removeValue(forKey: key)

        if let surfaceId,
           let activeHandle = surfaceHandlesById[surfaceId],
           surfaceKey(activeHandle) == key {
            surfaceHandlesById.removeValue(forKey: surfaceId)
            callbacksBySurfaceId.removeValue(forKey: surfaceId)
        }

        ghostty_surface_free(handle)
    }

    /// Updates app focus state so Ghostty can adapt key handling/behavior.
    func setAppFocus(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    /// Updates a specific surface focus state.
    func setSurfaceFocus(surfaceId: UUID, focused: Bool) {
        guard let surface = surfaceHandlesById[surfaceId] else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    /// Moves first-responder focus to the host view that owns a surface id.
    func focusSurfaceHost(surfaceId: UUID) {
        pendingFocusedSurfaceId = surfaceId
        guard let hostView = hostViewsBySurfaceId[surfaceId] else { return }
        if applyPendingFocusIfPossible(surfaceId: surfaceId, hostView: hostView) {
            return
        }

        DispatchQueue.main.async { [weak self, weak hostView] in
            guard let self, let hostView else { return }
            guard self.pendingFocusedSurfaceId == surfaceId else { return }
            _ = self.applyPendingFocusIfPossible(surfaceId: surfaceId, hostView: hostView)
        }
    }

    /// Applies a deferred focus request once a surface host is mounted into a window.
    func restorePendingFocusIfNeeded(surfaceId: UUID, hostView: any GhosttyFocusableHost) {
        guard pendingFocusedSurfaceId == surfaceId else { return }
        _ = applyPendingFocusIfPossible(surfaceId: surfaceId, hostView: hostView)
    }

    /// Attempts to hand AppKit first-responder focus to a mounted surface host.
    @discardableResult
    private func applyPendingFocusIfPossible(
        surfaceId: UUID,
        hostView: any GhosttyFocusableHost
    ) -> Bool {
        guard let window = hostView.hostWindow else { return false }

        window.makeKeyAndOrderFront(nil)
        if window.firstResponder !== hostView.firstResponderTarget {
            _ = window.makeFirstResponder(nil)
            guard window.makeFirstResponder(hostView.firstResponderTarget) else { return false }
        }

        setSurfaceFocus(surfaceId: surfaceId, focused: true)
        pendingFocusedSurfaceId = nil
        return true
    }

    /// Test-only access to pending focus state.
    var pendingFocusedSurfaceIdForTesting: UUID? {
        get { pendingFocusedSurfaceId }
        set { pendingFocusedSurfaceId = newValue }
    }

    /// Sends literal text input to a surface.
    @discardableResult
    func sendText(surfaceId: UUID, text: String) -> Bool {
        guard let surface = surfaceHandlesById[surfaceId] else { return false }
        guard !text.isEmpty else { return true }

        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }

        return true
    }

    /// Runs a named Ghostty binding action for a surface.
    @discardableResult
    func performBindingAction(surfaceId: UUID, action: String) -> Bool {
        guard let surface = surfaceHandlesById[surfaceId] else { return false }
        guard !action.isEmpty else { return false }

        return action.withCString { pointer in
            ghostty_surface_binding_action(surface, pointer, UInt(action.count))
        }
    }

    /// Sends a keyboard event to a surface using Ghostty's key encoding pipeline.
    func sendKeyEvent(
        surfaceId: UUID,
        event: NSEvent,
        action: ghostty_input_action_e,
        text: String? = nil,
        composing: Bool = false,
        modifiersOverride: NSEvent.ModifierFlags? = nil
    ) {
        guard let surface = surfaceHandlesById[surfaceId] else { return }
        let effectiveModifiers = modifiersOverride ?? event.modifierFlags

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = ghosttyMods(from: effectiveModifiers)
        keyEvent.consumed_mods = ghosttyConsumedMods(from: effectiveModifiers)
        keyEvent.unshifted_codepoint = 0
        keyEvent.text = nil
        keyEvent.composing = composing

        if let chars = event.characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        }

        if let text {
            text.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Sends a named control key directly to a surface via Ghostty's key-event path.
    @discardableResult
    func sendNamedKey(surfaceId: UUID, keyName: String) -> Bool {
        guard let mapping = scriptKeyMapping(for: keyName) else { return false }
        guard let keyDown = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: mapping.characters,
            charactersIgnoringModifiers: mapping.characters,
            isARepeat: false,
            keyCode: mapping.keyCode
        ) else {
            return false
        }

        guard let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: mapping.characters,
            charactersIgnoringModifiers: mapping.characters,
            isARepeat: false,
            keyCode: mapping.keyCode
        ) else {
            return false
        }

        sendKeyEvent(surfaceId: surfaceId, event: keyDown, action: GHOSTTY_ACTION_PRESS)
        sendKeyEvent(surfaceId: surfaceId, event: keyUp, action: GHOSTTY_ACTION_RELEASE)
        return true
    }

    /// Returns modifier flags translated by libghostty for the current surface settings.
    func translatedModifiers(surfaceId: UUID, from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        guard let surface = surfaceHandlesById[surfaceId] else { return flags }

        let translated = ghostty_surface_key_translation_mods(surface, ghosttyMods(from: flags))
        var result = flags
        let translatedFlags = nsModifierFlags(from: translated)

        for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
            if translatedFlags.contains(flag) {
                result.insert(flag)
            } else {
                result.remove(flag)
            }
        }

        return result
    }

    /// Reads unfocused split dimming style from Ghostty config keys.
    ///
    /// Mirrors Ghostty's own behavior:
    /// `unfocused-split-opacity` is an opacity for the unfocused split itself,
    /// so overlay opacity is `1 - value`.
    func unfocusedSplitStyle() -> UnfocusedSplitStyle {
        initializeIfNeeded()
        guard let config else {
            return UnfocusedSplitStyle(
                overlayOpacity: 0.3,
                fillColor: NSColor.windowBackgroundColor
            )
        }

        var splitOpacity: Double = 0.7
        let splitOpacityKey = "unfocused-split-opacity"
        _ = ghostty_config_get(config, &splitOpacity, splitOpacityKey, UInt(splitOpacityKey.count))
        let overlayOpacity = max(0, min(1, 1 - splitOpacity))

        var color = ghostty_config_color_s()
        let splitFillKey = "unfocused-split-fill"
        if !ghostty_config_get(config, &color, splitFillKey, UInt(splitFillKey.count)) {
            let backgroundKey = "background"
            _ = ghostty_config_get(config, &color, backgroundKey, UInt(backgroundKey.count))
        }

        let fillColor = NSColor(
            calibratedRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )

        return UnfocusedSplitStyle(overlayOpacity: overlayOpacity, fillColor: fillColor)
    }

    /// Reads pane chrome styling from Ghostty config keys.
    func chromeStyle() -> ChromeStyle {
        initializeIfNeeded()
        guard let config else {
            return ChromeStyle(
                backgroundColor: NSColor.windowBackgroundColor,
                foregroundColor: NSColor.labelColor,
                backgroundOpacity: 1,
                backgroundOpacityCells: false,
                backgroundBlurRadius: 0,
                splitDividerColor: NSColor.separatorColor
            )
        }

        let backgroundColor = configuredColor(
            config: config,
            key: "background"
        ) ?? NSColor.windowBackgroundColor

        let foregroundColor = configuredColor(
            config: config,
            key: "foreground"
        ) ?? NSColor.labelColor

        var backgroundOpacity: Double = 1
        let backgroundOpacityKey = "background-opacity"
        _ = ghostty_config_get(config, &backgroundOpacity, backgroundOpacityKey, UInt(backgroundOpacityKey.count))
        backgroundOpacity = max(0, min(1, backgroundOpacity))

        var backgroundOpacityCells = false
        let backgroundOpacityCellsKey = "background-opacity-cells"
        _ = ghostty_config_get(config, &backgroundOpacityCells, backgroundOpacityCellsKey, UInt(backgroundOpacityCellsKey.count))

        var backgroundBlurRadius: Int = 0
        let backgroundBlurKey = "background-blur"
        _ = ghostty_config_get(config, &backgroundBlurRadius, backgroundBlurKey, UInt(backgroundBlurKey.count))
        backgroundBlurRadius = max(0, backgroundBlurRadius)

        let splitDividerColor = configuredColor(
            config: config,
            key: "split-divider-color"
        ) ?? NSColor.separatorColor

        return ChromeStyle(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            backgroundOpacity: backgroundOpacity,
            backgroundOpacityCells: backgroundOpacityCells,
            backgroundBlurRadius: backgroundBlurRadius,
            splitDividerColor: splitDividerColor
        )
    }

    /// Reads a Ghostty color config value as an `NSColor`.
    private func configuredColor(config: ghostty_config_t, key: String) -> NSColor? {
        var color = ghostty_config_color_s()
        guard ghostty_config_get(config, &color, key, UInt(key.count)) else { return nil }
        return NSColor(
            calibratedRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    /// Maps AppleScript key names onto AppKit key event payloads.
    private func scriptKeyMapping(for keyName: String) -> (keyCode: UInt16, characters: String)? {
        switch keyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "enter", "return":
            return (36, "\r")
        case "tab":
            return (48, "\t")
        case "escape", "esc":
            return (53, "\u{1B}")
        case "backspace", "delete":
            return (51, "\u{7F}")
        default:
            return nil
        }
    }

    /// Initializes libghostty app/config/runtime callbacks exactly once.
    private func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup("schmux")]
        defer {
            for arg in argv where arg != nil {
                free(arg)
            }
        }

        _ = ghostty_init(UInt(argv.count), &argv)

        self.config = loadConfig()

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in
                GhosttyRuntime.wakeup(userdata)
            },
            action_cb: { app, target, action in
                guard let app else { return false }
                return GhosttyRuntime.action(app: app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, clipboard, requestState in
                GhosttyRuntime.readClipboard(
                    userdata: userdata,
                    clipboard: clipboard,
                    requestState: requestState
                )
            },
            confirm_read_clipboard_cb: { userdata, text, requestState, request in
                GhosttyRuntime.confirmReadClipboard(
                    userdata: userdata,
                    text: text,
                    requestState: requestState,
                    request: request
                )
            },
            write_clipboard_cb: { userdata, clipboard, content, contentCount, confirm in
                GhosttyRuntime.writeClipboard(
                    userdata: userdata,
                    clipboard: clipboard,
                    content: content,
                    contentCount: contentCount,
                    confirm: confirm
                )
            },
            close_surface_cb: { _, _ in }
        )

        self.app = ghostty_app_new(&runtimeConfig, config)
        setAppFocus(NSApp.isActive)

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setAppFocus(true)
            }
        }

        appDidResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setAppFocus(false)
            }
        }
    }

    /// Handles wakeup callback from libghostty.
    nonisolated private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }

        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            runtime.tickApp()
        }
    }

    /// Reads text from the host pasteboard and completes a pending Ghostty request.
    nonisolated private static func readClipboard(
        userdata: UnsafeMutableRawPointer?,
        clipboard: ghostty_clipboard_e,
        requestState: UnsafeMutableRawPointer?
    ) {
        guard let hostView = hostView(from: userdata) else { return }

        Task { @MainActor in
            guard let surface = hostView.surfaceHandleForCallbacks else { return }

            guard let target = clipboardTarget(from: clipboard),
                  let pasteboard = pasteboard(for: target) else {
                completeClipboardRequest(surface: surface, text: "", requestState: requestState)
                return
            }

            let text = pasteboard.opinionatedStringContents ?? ""
            completeClipboardRequest(surface: surface, text: text, requestState: requestState)
        }
    }

    /// Handles clipboard-read confirmation requests conservatively by denying them.
    nonisolated private static func confirmReadClipboard(
        userdata: UnsafeMutableRawPointer?,
        text: UnsafePointer<CChar>?,
        requestState: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        _ = text
        _ = request

        guard let hostView = hostView(from: userdata) else { return }

        Task { @MainActor in
            guard let surface = hostView.surfaceHandleForCallbacks else { return }
            completeClipboardRequest(
                surface: surface,
                text: "",
                requestState: requestState,
                confirmed: false
            )
        }
    }

    /// Writes terminal-provided clipboard content to the host pasteboard.
    nonisolated private static func writeClipboard(
        userdata: UnsafeMutableRawPointer?,
        clipboard: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        contentCount: Int,
        confirm: Bool
    ) {
        guard !confirm else { return }
        guard let target = clipboardTarget(from: clipboard),
              let pasteboard = pasteboard(for: target),
              let content,
              contentCount > 0 else {
            return
        }

        let items = (0..<contentCount).compactMap { index in
            ClipboardContent.from(content: content[index])
        }
        guard let string = items.first(where: { $0.mime.hasPrefix("text/plain") })?.data
            ?? items.first?.data else {
            return
        }

        Task { @MainActor in
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    /// Handles action callback from libghostty.
    nonisolated private static func action(
        app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard let appUserdata = ghostty_app_userdata(app) else { return false }
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(appUserdata).takeUnretainedValue()

        let event: SurfaceActionEvent?
        switch action.tag {
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            let surfaceKey = UInt(bitPattern: surface)
            event = .idleNotification
            DispatchQueue.main.async {
                runtime.handleAction(surfaceKey: surfaceKey, event: event!)
            }
            return true
        case GHOSTTY_ACTION_SET_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            let surfaceKey = UInt(bitPattern: surface)
            if let cTitle = action.action.set_title.title {
                event = .title(String(cString: cTitle))
                DispatchQueue.main.async {
                    runtime.handleAction(surfaceKey: surfaceKey, event: event!)
                }
                return true
            }
            return true
        case GHOSTTY_ACTION_PWD:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let rawWorkingDirectory = action.action.pwd.pwd else { return true }
            let surfaceKey = UInt(bitPattern: surface)
            event = .workingDirectory(String(cString: rawWorkingDirectory))
            DispatchQueue.main.async {
                runtime.handleAction(surfaceKey: surfaceKey, event: event!)
            }
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface else { return false }
            let surfaceKey = UInt(bitPattern: surface)
            event = .childExited
            DispatchQueue.main.async {
                runtime.handleAction(surfaceKey: surfaceKey, event: event!)
            }
            return true
        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async {
                runtime.ringBell()
            }
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            guard let rawURL = action.action.open_url.url else { return true }
            let urlString = string(from: rawURL, length: Int(action.action.open_url.len))
            DispatchQueue.main.async {
                runtime.openURL(urlString)
            }
            return true
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            let surfaceKey = target.tag == GHOSTTY_TARGET_SURFACE
                ? target.target.surface.map { UInt(bitPattern: $0) }
                : nil
            let soft = action.action.reload_config.soft
            DispatchQueue.main.async {
                runtime.reloadConfig(targetTag: target.tag, surfaceKey: surfaceKey, soft: soft)
            }
            return true
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            guard let clonedConfig = ghostty_config_clone(action.action.config_change.config) else {
                return true
            }
            let clonedConfigAddress = UInt(bitPattern: clonedConfig)
            let surfaceKey = target.tag == GHOSTTY_TARGET_SURFACE
                ? target.target.surface.map { UInt(bitPattern: $0) }
                : nil
            DispatchQueue.main.async {
                guard let config = UnsafeMutableRawPointer(bitPattern: clonedConfigAddress) else {
                    return
                }
                runtime.handleConfigChange(
                    targetTag: target.tag,
                    surfaceKey: surfaceKey,
                    config: config
                )
            }
            return true
        case GHOSTTY_ACTION_COLOR_CHANGE:
            DispatchQueue.main.async {
                runtime.notifyAppearanceDidChange()
            }
            return true
        default:
            return true
        }
    }

    /// Resolves the host view from a callback userdata pointer.
    nonisolated private static func hostView(from userdata: UnsafeMutableRawPointer?) -> LibghosttySurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<LibghosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    /// Resolves the embed clipboard enum into the host-facing target type.
    nonisolated private static func clipboardTarget(from clipboard: ghostty_clipboard_e) -> ClipboardTarget? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .standard
        case GHOSTTY_CLIPBOARD_SELECTION:
            return .selection
        default:
            return nil
        }
    }

    /// Returns the AppKit pasteboard for a Ghostty clipboard target.
    nonisolated private static func pasteboard(for target: ClipboardTarget) -> NSPasteboard? {
        switch target {
        case .standard:
            return .general
        case .selection:
            return NSPasteboard.ghosttySelection
        }
    }

    /// Completes a pending clipboard request back into libghostty.
    nonisolated private static func completeClipboardRequest(
        surface: ghostty_surface_t,
        text: String,
        requestState: UnsafeMutableRawPointer?,
        confirmed: Bool = false
    ) {
        text.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, requestState, confirmed)
        }
    }

    /// Executes one libghostty app tick cycle.
    private func tickApp() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// Loads a fresh Ghostty configuration from disk.
    private func loadConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        return config
    }

    /// Replaces the stored app-wide config and releases the old one.
    private func replaceStoredConfig(with newConfig: ghostty_config_t) {
        let previous = config
        config = newConfig

        if let previous, previous != newConfig {
            ghostty_config_free(previous)
        }
    }

    /// Reloads Ghostty configuration for the full app or a single surface.
    private func reloadConfig(targetTag: ghostty_target_tag_e, surfaceKey: UInt?, soft: Bool) {
        switch targetTag {
        case GHOSTTY_TARGET_APP:
            reloadAppConfig(soft: soft)
        case GHOSTTY_TARGET_SURFACE:
            guard let surfaceKey else { return }
            reloadSurfaceConfig(surfaceKey: surfaceKey, soft: soft)
        default:
            return
        }
    }

    /// Reloads the shared app configuration and refreshes dependent chrome.
    private func reloadAppConfig(soft: Bool) {
        guard let app, let config else { return }

        if soft {
            ghostty_app_update_config(app, config)
            notifyAppearanceDidChange()
            return
        }

        guard let newConfig = loadConfig() else { return }
        ghostty_app_update_config(app, newConfig)
        replaceStoredConfig(with: newConfig)
        notifyAppearanceDidChange()
    }

    /// Reloads configuration for a single surface when Ghostty requests it.
    private func reloadSurfaceConfig(surfaceKey: UInt, soft: Bool) {
        guard let surfaceId = surfaceIdsByHandle[surfaceKey],
              let surface = surfaceHandlesById[surfaceId] else {
            return
        }

        if soft {
            guard let config else { return }
            ghostty_surface_update_config(surface, config)
            notifyAppearanceDidChange()
            return
        }

        guard let newConfig = loadConfig() else { return }
        ghostty_surface_update_config(surface, newConfig)
        ghostty_config_free(newConfig)
        notifyAppearanceDidChange()
    }

    /// Stores config change notifications that originate from Ghostty itself.
    private func handleConfigChange(targetTag: ghostty_target_tag_e, surfaceKey: UInt?, config: ghostty_config_t) {
        switch targetTag {
        case GHOSTTY_TARGET_APP:
            replaceStoredConfig(with: config)
            notifyAppearanceDidChange()
        case GHOSTTY_TARGET_SURFACE:
            _ = surfaceKey
            ghostty_config_free(config)
            notifyAppearanceDidChange()
        default:
            ghostty_config_free(config)
        }
    }

    /// Opens a URL or file path requested by the terminal.
    private func openURL(_ urlString: String) {
        let urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        let url: URL
        if let candidate = URL(string: urlString), candidate.scheme != nil {
            url = candidate
        } else {
            url = URL(fileURLWithPath: urlString)
        }

        NSWorkspace.shared.open(url)
    }

    /// Emits the host bell for terminal alerts.
    private func ringBell() {
        NSSound.beep()
    }

    /// Posts a lightweight notification so SwiftUI chrome can redraw.
    private func notifyAppearanceDidChange() {
        NotificationCenter.default.post(name: Self.appearanceDidChangeNotification, object: nil)
    }

    /// Decodes a non-null-terminated C string buffer.
    nonisolated private static func string(from pointer: UnsafePointer<CChar>, length: Int) -> String {
        let buffer = UnsafeBufferPointer(start: pointer, count: max(0, length))
        let bytes = buffer.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Routes emitted actions to matching surface callbacks.
    private func handleAction(surfaceKey: UInt, event: SurfaceActionEvent) {
        guard let surfaceId = surfaceIdsByHandle[surfaceKey] else { return }
        guard let callbacks = callbacksBySurfaceId[surfaceId] else { return }

        switch event {
        case .idleNotification:
            callbacks.onIdleNotification()
        case .title(let title):
            callbacks.onTitleChange(title)
        case .workingDirectory(let workingDirectory):
            callbacks.onWorkingDirectoryChange(workingDirectory)
        case .childExited:
            callbacks.onChildExited()
        }
    }

    /// Creates the shell command passed into Ghostty surface creation.
    ///
    /// Ghostty's embedded API treats the provided command as a shell command,
    /// not a direct executable path. On macOS that command is additionally
    /// wrapped in login-shell startup behavior. To make an explicit working
    /// directory reliable, we enforce `cd` inside the launched command before
    /// handing execution to the requested shell.
    static func launchCommand(for terminalConfig: TerminalPanelConfig) -> String {
        launchCommand(
            shell: terminalConfig.shell,
            workingDirectory: effectiveWorkingDirectory(from: terminalConfig.workingDirectory)
        )
    }

    /// Creates the effective working directory used by runtime launch paths.
    static func effectiveWorkingDirectory(from workingDirectory: String) -> String? {
        let trimmedWorkingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWorkingDirectory.isEmpty else {
            return nil
        }
        return workingDirectory
    }

    /// Creates the shell command passed into Ghostty surface creation from normalized inputs.
    private static func launchCommand(shell: String, workingDirectory: String?) -> String {
        let escapedShell = shell.shellEscaped

        guard let workingDirectory else {
            return escapedShell
        }

        let script = "cd -- \(workingDirectory.shellEscaped) || exit $?; exec \(escapedShell)"
        return "\("/bin/sh".shellEscaped) -lc \(script.shellEscaped)"
    }

    /// Merges runtime environment variables for terminal launch.
    private func mergedEnvironment(
        for terminalConfig: TerminalPanelConfig,
        surfaceId: UUID
    ) -> [String: String] {
        var env = terminalConfig.environment
        env["SHELL"] = terminalConfig.shell
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        return AgentRuntimeBridge.shared.environment(
            for: surfaceId,
            shellPath: terminalConfig.shell,
            baseEnvironment: env
        )
    }

    /// Converts AppKit modifier flags to Ghostty modifier bits.
    private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        if flags.contains(.numericPad) { mods |= GHOSTTY_MODS_NUM.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    /// Approximates consumed mods similarly to Ghostty macOS integration.
    private func ghosttyConsumedMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        ghosttyMods(from: flags.subtracting([.control, .command]))
    }

    /// Converts Ghostty modifier bits back to AppKit modifier flags.
    private func nsModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    /// Returns a stable dictionary key for opaque surface pointers.
    private func surfaceKey(_ surface: ghostty_surface_t) -> UInt {
        UInt(bitPattern: surface)
    }

    /// Constructs `ghostty_surface_config_s` with temporary C string storage.
    private func withSurfaceConfig<T>(
        view: LibghosttySurfaceView,
        workingDirectory: String?,
        command: String?,
        environment: [String: String],
        body: (inout ghostty_surface_config_s) -> T
    ) -> T {
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(view).toOpaque())
        )
        config.userdata = Unmanaged.passUnretained(view).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)

        return withOptionalCString(workingDirectory) { workingDirectoryPtr in
            config.working_directory = workingDirectoryPtr

            return withOptionalCString(command) { commandPtr in
                config.command = commandPtr

                var envVars: [ghostty_env_var_s] = []
                var allocatedPointers: [UnsafeMutablePointer<CChar>] = []
                envVars.reserveCapacity(environment.count)

                for (key, value) in environment {
                    let keyPtr = strdup(key)
                    let valuePtr = strdup(value)

                    if let keyPtr, let valuePtr {
                        allocatedPointers.append(keyPtr)
                        allocatedPointers.append(valuePtr)
                        envVars.append(ghostty_env_var_s(key: UnsafePointer(keyPtr), value: UnsafePointer(valuePtr)))
                    }
                }

                defer {
                    for pointer in allocatedPointers {
                        free(pointer)
                    }
                }

                let envCount = envVars.count
                return envVars.withUnsafeMutableBufferPointer { buffer in
                    config.env_vars = buffer.baseAddress
                    config.env_var_count = envCount
                    return body(&config)
                }
            }
        }
    }
}

/// Utility for optional C string bridging with scoped pointer lifetime.
private func withOptionalCString<T>(_ value: String?, body: (UnsafePointer<CChar>?) -> T) -> T {
    guard let value else {
        return body(nil)
    }

    return value.withCString { pointer in
        body(pointer)
    }
}

private extension String {
    /// Single-quote shell escaping for `/bin/sh -c` command payloads.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension NSPasteboard {
    /// Dedicated selection pasteboard used for X11-style secondary selection semantics.
    static let ghosttySelection: NSPasteboard = {
        NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    }()

    /// Reads the most useful string representation available from the pasteboard.
    ///
    /// File URLs are converted to shell-safe absolute paths so paste operations behave
    /// like native terminal paste in the common case.
    var opinionatedStringContents: String? {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls
                .map { $0.isFileURL ? $0.path.shellEscaped : $0.absoluteString }
                .joined(separator: " ")
        }

        return string(forType: .string)
    }
}
#endif
