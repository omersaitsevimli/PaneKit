import AppKit
import ApplicationServices

/// Opens Layouts when the pointer is over a window’s green zoom button **and** Option is pressed.
///
/// Option gating avoids fragile hover-only detection and macOS’s own green-button menu race:
/// you aim at the traffic light, hold ⌥, Layouts appears — no separate hotkey hunt.
final class GreenButtonLayoutsTrigger {
    private let windowManager: WindowManager
    private let onShowLayouts: () -> Void
    private let isLayoutsVisible: () -> Bool

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var optionWasDown = false
    private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 0.55
    /// Extra hit padding around the AX zoom button (points).
    private let hitPadding: CGFloat = 6

    init(
        windowManager: WindowManager,
        onShowLayouts: @escaping () -> Void,
        isLayoutsVisible: @escaping () -> Bool
    ) {
        self.windowManager = windowManager
        self.onShowLayouts = onShowLayouts
        self.isLayoutsVisible = isLayoutsVisible
    }

    func start() {
        guard UserPreferences.shared.optionGreenButtonLayoutsEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        guard globalMonitor == nil else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .mouseMoved, .leftMouseDragged],
            handler: handler
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        optionWasDown = false
    }

    func reload() {
        stop()
        start()
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        let optionDown = event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)

        defer { optionWasDown = optionDown }

        guard UserPreferences.shared.optionGreenButtonLayoutsEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        guard !isLayoutsVisible() else { return }
        if DragSnapManager.isScreenshotUIActive() { return }

        // Primary: Option just pressed while already over the green button.
        let optionJustPressed = optionDown && !optionWasDown
        // Secondary: mouse moved onto the button while Option is held.
        let movingWithOption = optionDown && (event.type == .mouseMoved || event.type == .leftMouseDragged)

        guard optionJustPressed || movingWithOption else { return }
        guard isMouseOverZoomButton() else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= cooldown else { return }
        lastTriggerAt = now

        DispatchQueue.main.async { [weak self] in
            self?.onShowLayouts()
        }
    }

    // MARK: - Hit test

    private func isMouseOverZoomButton() -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let frame = zoomButtonCocoaFrameNearMouse(mouse) else { return false }
        return frame.insetBy(dx: -hitPadding, dy: -hitPadding).contains(mouse)
    }

    /// Prefer the focused window’s zoom button; fall back to frontmost app windows.
    private func zoomButtonCocoaFrameNearMouse(_ mouse: CGPoint) -> CGRect? {
        let paddedContains: (CGRect) -> Bool = { frame in
            frame.insetBy(dx: -self.hitPadding, dy: -self.hitPadding).contains(mouse)
        }

        if let focused = windowManager.focusedWindowElement(),
           let frame = zoomButtonCocoaFrame(of: focused),
           paddedContains(frame) {
            return frame
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows.prefix(6) {
            guard let frame = zoomButtonCocoaFrame(of: window), paddedContains(frame) else { continue }
            return frame
        }
        return nil
    }

    private func zoomButtonCocoaFrame(of window: AXUIElement) -> CGRect? {
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXZoomButtonAttribute as CFString,
            &buttonRef
        ) == .success,
              let button = buttonRef else {
            return nil
        }

        let axButton = button as! AXUIElement
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axButton, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(axButton, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        let axRect = CGRect(origin: position, size: size)
        return ScreenHelper.accessibilityToCocoa(axRect)
    }
}
