import AppKit
import ApplicationServices
import CoreGraphics

/// Drag-to-edge snapping with narrow, configurable magnet zones.
///
/// Narrow, cautious drag-to-snap:
/// - Only title-bar window drags (not content selection / arbitrary mouse-downs)
/// - Requires observed AX window movement before zones activate
/// - Ignores the rest of a rejected gesture until mouse-up
/// - Skips when macOS Screenshot UI is on-screen
/// - Default zone thickness is ~6pt; user-configurable
final class DragSnapManager {
    private let windowManager: WindowManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureState = DragGestureState()
    private var currentSnapAction: SnapAction?
    private var draggedWindow: AXUIElement?
    private var pendingDragPosition: CGPoint?
    private var dragUpdateScheduled = false
    /// While dragging along the bottom edge: last outer third visited (for two-thirds upgrade).
    private var bottomThirdAnchor: SnapAction?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        guard UserPreferences.shared.dragSnapEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        // listenOnly: we never swallow events (no extra Input Monitoring fight).
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<DragSnapManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.enqueueEvent(type: type, cursorPosition: event.location)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            NSLog("PaneKit: CGEvent tap for drag-snap could not be created")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        resetDragState()
        pendingDragPosition = nil
        dragUpdateScheduled = false
        eventTap = nil
        runLoopSource = nil
        DispatchQueue.main.async {
            SnapOverlayWindow.shared.hideOverlay()
        }
    }

    func reload() {
        stop()
        start()
    }

    // MARK: - Event routing

    private func enqueueEvent(type: CGEventType, cursorPosition: CGPoint) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            resetDragState()
            pendingDragPosition = nil
            dragUpdateScheduled = false
            DispatchQueue.main.async { SnapOverlayWindow.shared.hideOverlay() }
            return
        }

        switch type {
        case .leftMouseDragged:
            pendingDragPosition = cursorPosition
            guard !dragUpdateScheduled else { return }
            dragUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dragUpdateScheduled = false
                guard let latest = self.pendingDragPosition else { return }
                self.pendingDragPosition = nil
                self.handleDrag(cursorPosition: latest)
            }
        case .leftMouseUp:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let latest = self.pendingDragPosition {
                    self.pendingDragPosition = nil
                    self.handleDrag(cursorPosition: latest)
                }
                self.handleMouseUp(cursorPosition: cursorPosition)
            }
        default:
            break
        }
    }

    private func handleDrag(cursorPosition: CGPoint) {
        guard UserPreferences.shared.dragSnapEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }

        if !gestureState.isActive {
            if Self.isScreenshotUIActive() {
                gestureState.begin(
                    isCandidate: false,
                    cursorPosition: cursorPosition,
                    windowPosition: .zero
                )
                draggedWindow = nil
                currentSnapAction = nil
                return
            }

            guard let window = windowManager.focusedWindowElement(),
                  let frame = windowManager.frameAX(of: window) else { return }

            var windowPID: pid_t = 0
            guard AXUIElementGetPid(window, &windowPID) == .success else { return }

            // Never treat our own UI / overlays as a drag source.
            if windowPID == getpid() {
                gestureState.begin(
                    isCandidate: false,
                    cursorPosition: cursorPosition,
                    windowPosition: frame.origin
                )
                draggedWindow = nil
                currentSnapAction = nil
                return
            }

            let isCandidate = DragGestureState.isWindowDragCandidate(
                point: cursorPosition,
                windowPosition: frame.origin,
                windowSize: frame.size,
                windowPID: windowPID,
                topmostWindowPID: Self.topmostWindowOwnerPID(at: cursorPosition)
            )

            gestureState.begin(
                isCandidate: isCandidate,
                cursorPosition: cursorPosition,
                windowPosition: frame.origin
            )
            draggedWindow = isCandidate ? window : nil
            currentSnapAction = nil
            return
        }

        // Rejected gestures stay rejected until mouse-up.
        guard gestureState.isCandidate,
              let window = draggedWindow,
              let currentFrame = windowManager.frameAX(of: window) else { return }

        let decision = gestureState.update(
            cursorPosition: cursorPosition,
            currentWindowPosition: currentFrame.origin
        )

        switch decision {
        case .ignore, .wait:
            return
        case .detectSnapZone:
            break
        }

        let detected = detectSnapZone(cursorCG: cursorPosition)
        if detected != currentSnapAction {
            currentSnapAction = detected
            if let action = detected,
               let screen = Self.screen(forCGPoint: cursorPosition),
               let cocoa = action.snappedRect(on: screen) {
                SnapOverlayWindow.shared.show(at: cocoa)
            } else {
                SnapOverlayWindow.shared.hideOverlay()
            }
        }
    }

    private func handleMouseUp(cursorPosition: CGPoint) {
        let action = currentSnapAction
        let window = draggedWindow
        let wasDragging = gestureState.isActive && gestureState.isCandidate

        resetDragState()

        guard wasDragging, let action, let window else {
            SnapOverlayWindow.shared.hideOverlay()
            return
        }

        guard let screen = Self.screen(forCGPoint: cursorPosition) else {
            SnapOverlayWindow.shared.hideOverlay()
            return
        }

        guard let cocoa = action.snappedRect(on: screen) else {
            SnapOverlayWindow.shared.hideOverlay()
            return
        }
        windowManager.setCocoaFrame(window, cocoaFrame: cocoa, on: screen)
        SnapOverlayWindow.shared.hideOverlay()
    }

    private func resetDragState() {
        gestureState.reset()
        currentSnapAction = nil
        draggedWindow = nil
        bottomThirdAnchor = nil
    }

    // MARK: - Zone detection

    /// Pointer is Quartz/CG (Y down). Convert to Cocoa for NSScreen.frame math.
    ///
    /// Rectangle-style regions:
    /// - Corners → quarters
    /// - Left/right edge near top/bottom (outside corner) → top/bottom half
    /// - Left/right middle → left/right half
    /// - Top edge → maximize
    /// - Bottom edge thirds → left/center/right third; outer→center drag → two-thirds
    func detectSnapZone(cursorCG: CGPoint) -> SnapAction? {
        let prefs = UserPreferences.shared
        let edge = prefs.snapZoneThickness
        let corner = prefs.snapCornerRadius
        // Band along an edge, just outside the corner, that maps to top/bottom half.
        let sideHalfBand = max(corner * 1.5, 48)

        let cocoa = ScreenHelper.quartzPointToCocoa(cursorCG)
        guard let screen = Self.screen(containingCocoaPoint: cocoa) else {
            bottomThirdAnchor = nil
            return nil
        }
        let frame = screen.frame

        let distLeft = cocoa.x - frame.minX
        let distRight = frame.maxX - cocoa.x
        let distTop = frame.maxY - cocoa.y
        let distBottom = cocoa.y - frame.minY

        let nearLeft = distLeft < edge
        let nearRight = distRight < edge
        let nearTop = distTop < edge
        let nearBottom = distBottom < edge

        let inCornerLeft = distLeft < corner
        let inCornerRight = distRight < corner
        let inCornerTop = distTop < corner
        let inCornerBottom = distBottom < corner

        // 1) True corners → quarters
        if (nearTop && inCornerLeft) || (nearLeft && inCornerTop) { return .topLeft }
        if (nearTop && inCornerRight) || (nearRight && inCornerTop) { return .topRight }
        if (nearBottom && inCornerLeft) || (nearLeft && inCornerBottom) { return .bottomLeft }
        if (nearBottom && inCornerRight) || (nearRight && inCornerBottom) { return .bottomRight }

        // 2) Left / right edge: near-corner bands → top/bottom half; else side half
        if nearLeft {
            bottomThirdAnchor = nil
            if distTop < sideHalfBand { return .topHalf }
            if distBottom < sideHalfBand { return .bottomHalf }
            return .leftHalf
        }
        if nearRight {
            bottomThirdAnchor = nil
            if distTop < sideHalfBand { return .topHalf }
            if distBottom < sideHalfBand { return .bottomHalf }
            return .rightHalf
        }

        // 3) Top edge → maximize
        if nearTop {
            bottomThirdAnchor = nil
            return .maximize
        }

        // 4) Bottom edge → thirds / two-thirds (Rectangle bottom snap areas)
        if nearBottom {
            return detectBottomThirdZone(cocoaX: cocoa.x, frame: frame)
        }

        bottomThirdAnchor = nil
        return nil
    }

    /// Bottom edge: left / center / right third. Dragging from an outer third into
    /// the center upgrades to left/right two-thirds.
    private func detectBottomThirdZone(cocoaX: CGFloat, frame: CGRect) -> SnapAction {
        let width = frame.width
        let relative = cocoaX - frame.minX
        let third = width / 3
        let section: Int
        if relative < third {
            section = 0
        } else if relative < third * 2 {
            section = 1
        } else {
            section = 2
        }

        switch section {
        case 0:
            bottomThirdAnchor = .leftThird
            return .leftThird
        case 2:
            bottomThirdAnchor = .rightThird
            return .rightThird
        default:
            if bottomThirdAnchor == .leftThird {
                return .leftTwoThirds
            }
            if bottomThirdAnchor == .rightThird {
                return .rightTwoThirds
            }
            return .centerThird
        }
    }

    // MARK: - Helpers

    /// True while macOS Screenshot UI (⌘⇧3 / ⌘⇧4) is presenting selection chrome.
    static func isScreenshotUIActive() -> Bool {
        let screenshotBundleIDs: Set<String> = [
            "com.apple.screencaptureui",
            "com.apple.Screenshot",
        ]

        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           screenshotBundleIDs.contains(front) {
            return true
        }

        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for info in windows {
            if let bid = bundleID(forWindowInfo: info), screenshotBundleIDs.contains(bid) {
                return true
            }
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            if owner.contains("screenshot") || owner == "screencaptureui" {
                return true
            }
        }
        return false
    }

    private static func bundleID(forWindowInfo info: [String: Any]) -> String? {
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    static func topmostWindowOwnerPID(at point: CGPoint) -> pid_t? {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for info in windows {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"],
                  width > 0,
                  height > 0 else { continue }

            // Skip fully transparent overlay chrome when possible.
            if let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha < 0.05 {
                continue
            }

            let frame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: width,
                height: height
            )
            if frame.contains(point) {
                return ownerPID
            }
        }
        return nil
    }

    static func screen(forCGPoint point: CGPoint) -> NSScreen? {
        screen(containingCocoaPoint: ScreenHelper.quartzPointToCocoa(point))
    }

    static func screen(containingCocoaPoint point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen
        }
        return NSScreen.main
    }
}
