import AppKit
import ApplicationServices
import CoreGraphics

/// Drag the shared edge between two adjacent windows to grow one and shrink the other.
///
/// Only activates on a *shared seam* (two windows already touching) with a narrow hit
/// zone — not on every window edge — so screenshots / text selection stay usable.
final class SplitResizeManager {
    private enum Axis {
        case vertical // left | right
        case horizontal // top / bottom (AX Y grows downward)
    }

    private struct Seam {
        let axis: Axis
        let primary: AXUIElement // left or top
        let secondary: AXUIElement // right or bottom
        let primaryFrame: CGRect
        let secondaryFrame: CGRect
        let divider: CGFloat
        let overlapStart: CGFloat
        let overlapEnd: CGFloat
    }

    private struct Session {
        let seam: Seam
        let minPrimary: CGFloat
        let maxPrimary: CGFloat
        var lastDivider: CGFloat
        var lastPrimaryFrame: CGRect
        var lastSecondaryFrame: CGRect
    }

    private let windowManager: WindowManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session: Session?
    private var chromeDisabledPIDs: Set<pid_t> = []

    /// Gap between windows still treated as “touching”.
    private let maxGap: CGFloat = 4
    /// Half-width of the grab strip around the seam.
    private let hitThickness: CGFloat = 5
    private let minSpan: CGFloat = 180

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() {
        guard UserPreferences.shared.splitResizeEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<SplitResizeManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handle(type: type, quartzPoint: event.location)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            NSLog("PaneKit: CGEvent tap for split-resize could not be created")
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
        session = nil
        chromeDisabledPIDs.removeAll()
        eventTap = nil
        runLoopSource = nil
        DispatchQueue.main.async {
            NSCursor.arrow.set()
        }
    }

    func reload() {
        stop()
        start()
    }

    // MARK: - Events

    private func handle(type: CGEventType, quartzPoint: CGPoint) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        // Drag updates run immediately on the main queue (no second async coalesce)
        // so the trailing window tracks the pointer instead of lagging a frame behind.
        if Thread.isMainThread {
            handleOnMain(type: type, point: quartzPoint)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleOnMain(type: type, point: quartzPoint)
            }
        }
    }

    private func handleOnMain(type: CGEventType, point: CGPoint) {
        switch type {
        case .leftMouseDown:
            beginIfNeeded(at: point)
        case .leftMouseDragged:
            guard session != nil else { return }
            applyDrag(at: point)
        case .leftMouseUp:
            endSession()
        default:
            break
        }
    }

    private func beginIfNeeded(at point: CGPoint) {
        session = nil
        guard UserPreferences.shared.splitResizeEnabled else { return }
        guard AccessibilityPermission.isTrusted else { return }
        if DragSnapManager.isScreenshotUIActive() { return }

        guard let seam = findSeam(at: point) else { return }

        let combined: CGFloat
        let minPrimary: CGFloat
        let maxPrimary: CGFloat
        switch seam.axis {
        case .vertical:
            combined = seam.primaryFrame.width + seam.secondaryFrame.width
            minPrimary = minSpan
            maxPrimary = combined - minSpan
        case .horizontal:
            combined = seam.primaryFrame.height + seam.secondaryFrame.height
            minPrimary = minSpan
            maxPrimary = combined - minSpan
        }

        guard maxPrimary > minPrimary else { return }

        prepareChrome(for: seam.primary)
        prepareChrome(for: seam.secondary)

        session = Session(
            seam: seam,
            minPrimary: minPrimary,
            maxPrimary: maxPrimary,
            lastDivider: seam.divider,
            lastPrimaryFrame: seam.primaryFrame,
            lastSecondaryFrame: seam.secondaryFrame
        )
        switch seam.axis {
        case .vertical:
            NSCursor.resizeLeftRight.set()
        case .horizontal:
            NSCursor.resizeUpDown.set()
        }
    }

    private func prepareChrome(for window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != 0, !chromeDisabledPIDs.contains(pid) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanFalse
        )
        chromeDisabledPIDs.insert(pid)
    }

    private func applyDrag(at point: CGPoint) {
        guard var session else { return }
        let seam = session.seam

        let newDivider: CGFloat
        let primary: CGRect
        let secondary: CGRect

        switch seam.axis {
        case .vertical:
            newDivider = min(max(point.x, seam.primaryFrame.minX + session.minPrimary),
                             seam.primaryFrame.minX + session.maxPrimary)
            // Skip sub-pixel noise — still feels instant, less AX spam.
            guard abs(newDivider - session.lastDivider) >= 0.5 else { return }
            var left = seam.primaryFrame
            var right = seam.secondaryFrame
            left.size.width = newDivider - left.minX
            right.origin.x = newDivider
            right.size.width = seam.secondaryFrame.maxX - newDivider
            primary = left
            secondary = right

        case .horizontal:
            newDivider = min(max(point.y, seam.primaryFrame.minY + session.minPrimary),
                             seam.primaryFrame.minY + session.maxPrimary)
            guard abs(newDivider - session.lastDivider) >= 0.5 else { return }
            var top = seam.primaryFrame
            var bottom = seam.secondaryFrame
            top.size.height = newDivider - top.minY
            bottom.origin.y = newDivider
            bottom.size.height = seam.secondaryFrame.maxY - newDivider
            primary = top
            secondary = bottom
        }

        // Secondary (right/bottom) first — that’s the window users perceive as “lagging”.
        windowManager.setAXFrameLive(seam.secondary, frame: secondary)
        windowManager.setAXFrameLive(seam.primary, frame: primary)

        session.lastDivider = newDivider
        session.lastPrimaryFrame = primary
        session.lastSecondaryFrame = secondary
        self.session = session
    }

    private func endSession() {
        if let session {
            // One solid finalize so apps that skipped live frames settle exactly.
            windowManager.setAXFrameFinal(session.seam.secondary, frame: session.lastSecondaryFrame)
            windowManager.setAXFrameFinal(session.seam.primary, frame: session.lastPrimaryFrame)
            NSCursor.arrow.set()
        }
        session = nil
    }

    // MARK: - Seam discovery

    private func findSeam(at point: CGPoint) -> Seam? {
        let candidates = windowManager.listCandidateWindows()
        guard candidates.count >= 2 else { return nil }

        var windows: [(AXUIElement, CGRect)] = []
        windows.reserveCapacity(candidates.count)
        for managed in candidates {
            guard let frame = windowManager.frameAX(of: managed.element) else { continue }
            windows.append((managed.element, frame))
        }

        var best: Seam?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for i in 0..<windows.count {
            for j in (i + 1)..<windows.count {
                let a = windows[i]
                let b = windows[j]

                if let seam = verticalSeam(a, b), let distance = distanceToVerticalSeam(point, seam) {
                    if distance < bestDistance {
                        bestDistance = distance
                        best = seam
                    }
                }
                if let seam = horizontalSeam(a, b), let distance = distanceToHorizontalSeam(point, seam) {
                    if distance < bestDistance {
                        bestDistance = distance
                        best = seam
                    }
                }
            }
        }

        return best
    }

    private func verticalSeam(
        _ a: (AXUIElement, CGRect),
        _ b: (AXUIElement, CGRect)
    ) -> Seam? {
        let left: (AXUIElement, CGRect)
        let right: (AXUIElement, CGRect)
        if abs(a.1.maxX - b.1.minX) <= maxGap {
            left = a
            right = b
        } else if abs(b.1.maxX - a.1.minX) <= maxGap {
            left = b
            right = a
        } else {
            return nil
        }

        let overlapStart = max(left.1.minY, right.1.minY)
        let overlapEnd = min(left.1.maxY, right.1.maxY)
        guard overlapEnd - overlapStart >= min(minSpan, min(left.1.height, right.1.height) * 0.35) else {
            return nil
        }

        let divider = (left.1.maxX + right.1.minX) / 2
        return Seam(
            axis: .vertical,
            primary: left.0,
            secondary: right.0,
            primaryFrame: left.1,
            secondaryFrame: right.1,
            divider: divider,
            overlapStart: overlapStart,
            overlapEnd: overlapEnd
        )
    }

    private func horizontalSeam(
        _ a: (AXUIElement, CGRect),
        _ b: (AXUIElement, CGRect)
    ) -> Seam? {
        let top: (AXUIElement, CGRect)
        let bottom: (AXUIElement, CGRect)
        // AX Y grows downward: smaller Y is higher on screen.
        if abs(a.1.maxY - b.1.minY) <= maxGap {
            top = a
            bottom = b
        } else if abs(b.1.maxY - a.1.minY) <= maxGap {
            top = b
            bottom = a
        } else {
            return nil
        }

        let overlapStart = max(top.1.minX, bottom.1.minX)
        let overlapEnd = min(top.1.maxX, bottom.1.maxX)
        guard overlapEnd - overlapStart >= min(minSpan, min(top.1.width, bottom.1.width) * 0.35) else {
            return nil
        }

        let divider = (top.1.maxY + bottom.1.minY) / 2
        return Seam(
            axis: .horizontal,
            primary: top.0,
            secondary: bottom.0,
            primaryFrame: top.1,
            secondaryFrame: bottom.1,
            divider: divider,
            overlapStart: overlapStart,
            overlapEnd: overlapEnd
        )
    }

    private func distanceToVerticalSeam(_ point: CGPoint, _ seam: Seam) -> CGFloat? {
        guard point.y >= seam.overlapStart - hitThickness,
              point.y <= seam.overlapEnd + hitThickness else { return nil }
        let dx = abs(point.x - seam.divider)
        guard dx <= hitThickness else { return nil }
        return dx
    }

    private func distanceToHorizontalSeam(_ point: CGPoint, _ seam: Seam) -> CGFloat? {
        guard point.x >= seam.overlapStart - hitThickness,
              point.x <= seam.overlapEnd + hitThickness else { return nil }
        let dy = abs(point.y - seam.divider)
        guard dy <= hitThickness else { return nil }
        return dy
    }
}
