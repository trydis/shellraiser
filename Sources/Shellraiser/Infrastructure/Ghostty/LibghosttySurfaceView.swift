import AppKit
import Foundation
#if canImport(GhosttyKit)
import GhosttyKit

/// AppKit view that owns one live libghostty surface.
final class LibghosttySurfaceView: NSView, NSTextInputClient, NSMenuItemValidation, NSServicesMenuRequestor {
    private var surfaceModel: SurfaceModel
    private var terminalConfig: TerminalPanelConfig

    private var surfaceHandle: ghostty_surface_t?
    private var onActivate: () -> Void
    private var onIdleNotification: () -> Void
    private var onUserInput: () -> Void
    private var onTitleChange: (String) -> Void
    private var onWorkingDirectoryChange: (String) -> Void
    private var onChildExited: () -> Void
    private var onPaneNavigationRequest: (PaneNodeModel.PaneFocusDirection) -> Void
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var didInterpretCommand = false

    /// Stable identifier for the surface hosted by this view.
    var surfaceId: UUID { surfaceModel.id }

    /// Internal surface handle used by runtime callbacks.
    var surfaceHandleForCallbacks: ghostty_surface_t? { surfaceHandle }

    /// Creates a new host view and its libghostty surface.
    init(
        surfaceModel: SurfaceModel,
        terminalConfig: TerminalPanelConfig,
        onActivate: @escaping () -> Void,
        onIdleNotification: @escaping () -> Void,
        onUserInput: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onWorkingDirectoryChange: @escaping (String) -> Void,
        onChildExited: @escaping () -> Void,
        onPaneNavigationRequest: @escaping (PaneNodeModel.PaneFocusDirection) -> Void
    ) {
        self.surfaceModel = surfaceModel
        self.terminalConfig = terminalConfig
        self.onActivate = onActivate
        self.onIdleNotification = onIdleNotification
        self.onUserInput = onUserInput
        self.onTitleChange = onTitleChange
        self.onWorkingDirectoryChange = onWorkingDirectoryChange
        self.onChildExited = onChildExited
        self.onPaneNavigationRequest = onPaneNavigationRequest
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        wantsLayer = true
        let metalLayer = CAMetalLayer()
        metalLayer.isOpaque = true
        layer = metalLayer
        layer?.isOpaque = true
        applyGhosttyBackgroundStyle()

        GhosttyRuntime.shared.registerSurfaceCallbacks(
            surfaceId: surfaceModel.id,
            onIdleNotification: onIdleNotification,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited
        )
        surfaceHandle = GhosttyRuntime.shared.createSurface(
            for: self,
            surfaceModel: surfaceModel,
            terminalConfig: terminalConfig
        )
        updateScaleAndSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        shutdown()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        GhosttyRuntime.shared.setAppFocus(NSApp.isActive)
        GhosttyRuntime.shared.restorePendingFocusIfNeeded(surfaceId: surfaceModel.id, hostView: self)
        updateScaleAndSize()
        updateDisplayIdentifier()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateScaleAndSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScaleAndSize()
        updateDisplayIdentifier()
    }

    /// Rebuilds tracking regions so Ghostty receives hover and motion events.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea(_:))

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onActivate()
            GhosttyRuntime.shared.setSurfaceFocus(surfaceId: surfaceModel.id, focused: true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            GhosttyRuntime.shared.setSurfaceFocus(surfaceId: surfaceModel.id, focused: false)
        }
        return result
    }

    /// Intercepts command-equivalent pane navigation before keyDown dispatch.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let direction = paneNavigationDirection(for: event) {
            onPaneNavigationRequest(direction)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// Handles key down using AppKit text interpretation for IME/dead-key correctness.
    override func keyDown(with event: NSEvent) {
        if let direction = paneNavigationDirection(for: event) {
            onPaneNavigationRequest(direction)
            return
        }

        let translatedModifiers = GhosttyRuntime.shared.translatedModifiers(
            surfaceId: surfaceModel.id,
            from: event.modifierFlags
        )

        let translatedEvent = translatedKeyEvent(from: event, modifiers: translatedModifiers)
        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let markedTextBefore = markedText.length > 0

        // Route raw Tab and Shift+Tab straight to Ghostty so terminal UIs receive
        // their own mode-switch bindings instead of AppKit text-system handling.
        if event.keyCode == 48,
           !translatedEvent.modifierFlags.contains(.command),
           !translatedEvent.modifierFlags.contains(.control),
           !translatedEvent.modifierFlags.contains(.option) {
            onUserInput()
            GhosttyRuntime.shared.sendKeyEvent(
                surfaceId: surfaceModel.id,
                event: event,
                action: action,
                modifiersOverride: translatedEvent.modifierFlags
            )
            return
        }

        keyTextAccumulator = []
        didInterpretCommand = false
        defer {
            keyTextAccumulator = nil
            didInterpretCommand = false
        }

        interpretKeyEvents([translatedEvent])
        syncPreedit(clearIfNeeded: markedTextBefore)
        let composing = Self.isComposing(markedTextLength: markedText.length, markedTextBefore: markedTextBefore)

        if let textEvents = keyTextAccumulator, !textEvents.isEmpty {
            for text in textEvents {
                onUserInput()
                GhosttyRuntime.shared.sendKeyEvent(
                    surfaceId: surfaceModel.id,
                    event: event,
                    action: action,
                    text: text,
                    composing: false,
                    modifiersOverride: translatedEvent.modifierFlags
                )
            }
            return
        }

        if didInterpretCommand {
            onUserInput()
            GhosttyRuntime.shared.sendKeyEvent(
                surfaceId: surfaceModel.id,
                event: event,
                action: action,
                composing: composing,
                modifiersOverride: translatedEvent.modifierFlags
            )
            return
        }

        onUserInput()
        GhosttyRuntime.shared.sendKeyEvent(
            surfaceId: surfaceModel.id,
            event: event,
            action: action,
            text: Self.fallbackTextPayload(
                interpretedCommand: didInterpretCommand,
                characters: translatedEvent.characters
            ),
            composing: composing,
            modifiersOverride: translatedEvent.modifierFlags
        )
    }

    /// Sends key release events to Ghostty.
    override func keyUp(with event: NSEvent) {
        GhosttyRuntime.shared.sendKeyEvent(surfaceId: surfaceModel.id, event: event, action: GHOSTTY_ACTION_RELEASE)
    }

    /// Forwards left-button press events to libghostty.
    override func mouseDown(with event: NSEvent) {
        guard let surfaceHandle else { return }
        onActivate()
        ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, ghosttyMods(from: event.modifierFlags))
    }

    /// Forwards left-button release events to libghostty.
    override func mouseUp(with event: NSEvent) {
        guard let surfaceHandle else { return }
        ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(from: event.modifierFlags))
        ghostty_surface_mouse_pressure(surfaceHandle, 0, 0)
    }

    /// Forwards middle-button press events to libghostty.
    override func otherMouseDown(with event: NSEvent) {
        guard let surfaceHandle, event.buttonNumber == 2 else { return }
        ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, ghosttyMods(from: event.modifierFlags))
    }

    /// Forwards middle-button release events to libghostty.
    override func otherMouseUp(with event: NSEvent) {
        guard let surfaceHandle, event.buttonNumber == 2 else { return }
        ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, ghosttyMods(from: event.modifierFlags))
    }

    /// Forwards right-button press events to libghostty before falling back to AppKit.
    override func rightMouseDown(with event: NSEvent) {
        guard let surfaceHandle else {
            super.rightMouseDown(with: event)
            return
        }

        if ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, ghosttyMods(from: event.modifierFlags)) {
            return
        }

        super.rightMouseDown(with: event)
    }

    /// Forwards right-button release events to libghostty before falling back to AppKit.
    override func rightMouseUp(with event: NSEvent) {
        guard let surfaceHandle else {
            super.rightMouseUp(with: event)
            return
        }

        if ghostty_surface_mouse_button(surfaceHandle, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghosttyMods(from: event.modifierFlags)) {
            return
        }

        super.rightMouseUp(with: event)
    }

    /// Resets cursor position when the mouse enters the terminal surface.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        sendMousePosition(for: event)
    }

    /// Clears cursor position when the mouse exits the terminal surface.
    override func mouseExited(with event: NSEvent) {
        guard let surfaceHandle else { return }
        ghostty_surface_mouse_pos(surfaceHandle, -1, -1, ghosttyMods(from: event.modifierFlags))
    }

    /// Forwards hover movement events to libghostty.
    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(for: event)
    }

    /// Reuses hover logic for drag updates.
    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    /// Reuses hover logic for right-button drag updates.
    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    /// Reuses hover logic for middle-button drag updates.
    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    /// Forwards scroll-wheel deltas to libghostty.
    override func scrollWheel(with event: NSEvent) {
        guard let surfaceHandle else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }

        ghostty_surface_mouse_scroll(surfaceHandle, x, y, scrollMods(from: event))
    }

    /// Reports pressure changes so libghostty can handle force-click interactions.
    override func pressureChange(with event: NSEvent) {
        guard let surfaceHandle else { return }
        ghostty_surface_mouse_pressure(surfaceHandle, UInt32(event.stage), Double(event.pressure))
    }

    /// Decodes Option+Command+Arrow as pane navigation regardless of event routing path.
    private func paneNavigationDirection(for event: NSEvent) -> PaneNodeModel.PaneFocusDirection? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains([.command, .option]) else { return nil }

        if let specialKey = event.specialKey {
            switch specialKey {
            case .leftArrow: return .left
            case .rightArrow: return .right
            case .upArrow: return .up
            case .downArrow: return .down
            default: break
            }
        }

        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    /// Returns an event with translated modifier flags for consistent key encoding.
    private func translatedKeyEvent(from event: NSEvent, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        guard modifiers != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: modifiers,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: modifiers) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    /// Forwards the current cursor position to libghostty in surface coordinates.
    private func sendMousePosition(for event: NSEvent) {
        guard let surfaceHandle else { return }
        let position = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surfaceHandle,
            position.x,
            frame.height - position.y,
            ghosttyMods(from: event.modifierFlags)
        )
    }

    /// Synchronizes AppKit marked text (preedit) with libghostty.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surfaceHandle else { return }

        if markedText.length > 0 {
            let string = markedText.string
            let utf8Count = string.utf8CString.count
            guard utf8Count > 0 else { return }
            string.withCString { ptr in
                ghostty_surface_preedit(surfaceHandle, ptr, UInt(utf8Count - 1))
            }
            return
        }

        if clearIfNeeded {
            ghostty_surface_preedit(surfaceHandle, nil, 0)
        }
    }

    /// Applies updated view model values for future operations.
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
    ) {
        self.surfaceModel = surfaceModel
        self.terminalConfig = terminalConfig
        self.onActivate = onActivate
        self.onIdleNotification = onIdleNotification
        self.onUserInput = onUserInput
        self.onTitleChange = onTitleChange
        self.onWorkingDirectoryChange = onWorkingDirectoryChange
        self.onChildExited = onChildExited
        self.onPaneNavigationRequest = onPaneNavigationRequest

        GhosttyRuntime.shared.registerSurfaceCallbacks(
            surfaceId: surfaceModel.id,
            onIdleNotification: onIdleNotification,
            onTitleChange: onTitleChange,
            onWorkingDirectoryChange: onWorkingDirectoryChange,
            onChildExited: onChildExited
        )
        applyGhosttyBackgroundStyle()
        updateScaleAndSize()
    }

    /// Releases any owned libghostty surface resources.
    func shutdown() {
        guard let surfaceHandle else { return }
        self.surfaceHandle = nil
        GhosttyRuntime.shared.destroySurface(handle: surfaceHandle)
    }

    /// Updates libghostty with current DPI scale and framebuffer size.
    private func updateScaleAndSize() {
        guard let handle = surfaceHandle else { return }

        let frame = bounds.size
        guard frame.width > 0, frame.height > 0 else { return }

        let backingRect = convertToBacking(NSRect(origin: .zero, size: frame))
        let xScale = backingRect.width / max(frame.width, 1)
        let yScale = backingRect.height / max(frame.height, 1)

        ghostty_surface_set_content_scale(handle, xScale, yScale)
        ghostty_surface_set_size(handle, UInt32(backingRect.width), UInt32(backingRect.height))
    }

    /// Applies Ghostty-configured background color to the host layer backing.
    private func applyGhosttyBackgroundStyle() {
        let style = GhosttyRuntime.shared.chromeStyle()
        let baseColor = style.backgroundColor.usingColorSpace(.deviceRGB) ?? style.backgroundColor
        layer?.backgroundColor = baseColor.withAlphaComponent(1).cgColor
    }

    /// Informs libghostty when the host view moves between displays.
    private func updateDisplayIdentifier() {
        guard let surfaceHandle else { return }
        let displayId = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        ghostty_surface_set_display_id(surfaceHandle, displayId?.uint32Value ?? 0)
    }

    /// Reports whether AppKit currently tracks marked text.
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    /// Returns marked text range expected by `NSTextInputClient`.
    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(location: 0, length: markedText.length)
    }

    /// Returns current selected range; selection querying is not implemented yet.
    func selectedRange() -> NSRange {
        guard let surfaceHandle else { return NSRange() }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surfaceHandle, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surfaceHandle, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    /// Stores marked text and updates preedit when needed.
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String:
            markedText = NSMutableAttributedString(string: plain)
        default:
            return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    /// Clears marked text and preedit state.
    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    /// Returns valid attributes for marked text. We do not support custom attributes.
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Returns attributed substring for the proposed range. Selection extraction is unsupported.
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let surfaceHandle else { return nil }
        guard range.length > 0 else { return nil }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surfaceHandle, &text) else { return nil }
        defer { ghostty_surface_free_text(surfaceHandle, &text) }
        return NSAttributedString(string: String(cString: text.text))
    }

    /// Returns text index for the given point. Cursor indexing is unsupported.
    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    /// Returns IME candidate anchor rectangle in screen coordinates.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surfaceHandle else { return convert(bounds, to: nil) }

        var x = 0.0
        var y = 0.0
        var width = 0.0
        var height = 0.0
        ghostty_surface_ime_point(surfaceHandle, &x, &y, &width, &height)

        let viewRect = NSRect(
            x: x,
            y: bounds.height - y,
            width: max(width, 1),
            height: max(height, 1)
        )
        let windowRect = convert(viewRect, to: nil)
        guard let window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    /// Handles committed text from AppKit input methods.
    func insertText(_ string: Any, replacementRange: NSRange) {
        var text = ""
        switch string {
        case let attributed as NSAttributedString:
            text = attributed.string
        case let plain as String:
            text = plain
        default:
            return
        }

        unmarkText()

        if var accumulator = keyTextAccumulator {
            accumulator.append(text)
            keyTextAccumulator = accumulator
            return
        }

        guard !text.isEmpty else { return }
        onUserInput()
        GhosttyRuntime.shared.sendText(surfaceId: surfaceModel.id, text: text)
    }

    /// Exposes copy support to the AppKit responder chain.
    @objc func copy(_ sender: Any?) {
        _ = GhosttyRuntime.shared.performBindingAction(
            surfaceId: surfaceModel.id,
            action: "copy_to_clipboard"
        )
    }

    /// Exposes paste support to the AppKit responder chain.
    @objc func paste(_ sender: Any?) {
        onUserInput()
        _ = GhosttyRuntime.shared.performBindingAction(
            surfaceId: surfaceModel.id,
            action: "paste_from_clipboard"
        )
    }

    /// Exposes select-all support via the native Ghostty binding pipeline.
    override func selectAll(_ sender: Any?) {
        _ = GhosttyRuntime.shared.performBindingAction(
            surfaceId: surfaceModel.id,
            action: "select_all"
        )
    }

    /// Publishes the current selection to services and other AppKit responders.
    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let surfaceHandle else { return false }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surfaceHandle, &text) else { return false }
        defer { ghostty_surface_free_text(surfaceHandle, &text) }

        pboard.clearContents()
        pboard.setString(String(cString: text.text), forType: .string)
        return true
    }

    /// Accepts AppKit service paste operations.
    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let text = pboard.opinionatedStringContents, !text.isEmpty else { return false }
        onUserInput()
        GhosttyRuntime.shared.sendText(surfaceId: surfaceModel.id, text: text)
        return true
    }

    /// Advertises supported send/receive service combinations.
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        let supported: [NSPasteboard.PasteboardType] = [.string, .init("public.utf8-plain-text")]
        let canReceive = returnType == nil || supported.contains(returnType!)
        let canSend = sendType == nil || supported.contains(sendType!)
        guard canReceive, canSend else {
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        if let sendType, supported.contains(sendType), !hasSelection {
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        return self
    }

    /// Enables and disables menu items based on current selection state.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)):
            return hasSelection
        case #selector(paste(_:)):
            return !(NSPasteboard.general.opinionatedStringContents?.isEmpty ?? true)
        default:
            return true
        }
    }

    /// Marks interpreted AppKit commands so the original key event is forwarded without text.
    override func doCommand(by selector: Selector) {
        _ = selector
        didInterpretCommand = true
    }

    /// Chooses the fallback text payload for interpreted key events.
    static func fallbackTextPayload(interpretedCommand: Bool, characters: String?) -> String? {
        guard !interpretedCommand else { return nil }
        return characters ?? ""
    }

    /// Returns whether the current key path is handling an active IME composition.
    static func isComposing(markedTextLength: Int, markedTextBefore: Bool) -> Bool {
        markedTextLength > 0 || markedTextBefore
    }

    /// Returns whether the terminal currently has a text selection.
    private var hasSelection: Bool {
        guard let surfaceHandle else { return false }
        return ghostty_surface_has_selection(surfaceHandle)
    }

    /// Converts AppKit modifier flags to Ghostty modifier bits for mouse input.
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

    /// Converts AppKit scrolling metadata to Ghostty's packed scroll-modifier bitfield.
    private func scrollMods(from event: NSEvent) -> ghostty_input_scroll_mods_t {
        var result: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            result |= 1
        }

        let momentumValue = ghostty_input_scroll_mods_t(event.momentumPhase.rawValue << 1)
        result |= momentumValue
        return result
    }
}

extension LibghosttySurfaceView: GhosttyFocusableHost {
    /// Window currently hosting the terminal surface view.
    var hostWindow: NSWindow? { window }

    /// First-responder target used for AppKit focus restoration.
    var firstResponderTarget: NSResponder { self }
}
#endif
