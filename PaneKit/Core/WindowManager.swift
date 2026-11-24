import AppKit
import ApplicationServices

/// Remembers pre-snap frames so Restore can undo the last snap per window.
private struct WindowFrameHistory {
    private let capacity: Int
    private var frames: [String: CGRect] = [:]
    private var insertionOrder: [String] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func frame(for windowID: String) -> CGRect? {
        frames[windowID]
    }

    mutating func remember(_ frame: CGRect, for windowID: String) {
        // Keep the original pre-snap frame until Restore clears it.
        guard frames[windowID] == nil else { return }
        frames[windowID] = frame
        insertionOrder.append(windowID)
        while insertionOrder.count > capacity {
            let expired = insertionOrder.removeFirst()
            frames.removeValue(forKey: expired)
        }
    }

    mutating func forget(windowID: String) {
        frames.removeValue(forKey: windowID)
        insertionOrder.removeAll { $0 == windowID }
    }
}

/// Moves / resizes windows via the Accessibility API and lists candidates for layouts.
final class WindowManager {
    private var frameHistory = WindowFrameHistory(capacity: 128)
    /// Tracks the hotkey entry + last applied size so repeats can size-cycle, then monitor-cycle.
    private var lastSnapAction: (
        windowID: String,
        entryAction: SnapAction,
        appliedAction: SnapAction,
        screenKey: String
    )?
    /// When set, snaps while the pin app is focused reflow the sidebar instead of tiling into work area.
    var pinModeReflow: (() -> Void)?
    /// Restores the last saved workspace (⌃⌥P).
    var restoreLastWorkspaceHandler: (() -> Void)?
    var stashToggleHandler: (() -> Void)?
    var unstashAllHandler: (() -> Void)?
    /// When set, stashed windows are skipped by tile-all / similar multi-window ops.
    var isWindowStashed: ((String) -> Bool)?

    private enum TileMode {
        case rows
        case columns
    }

    /// Last tile-all layout so repeating the shortcut cycles grids.
    private var lastTileState: (screenKey: String, mode: TileMode, index: Int, signature: String)?

    func snap(_ action: SnapAction) {
        // Do not re-prompt here — Layouts/snap hot paths must stay quiet once denied.
        guard AccessibilityPermission.isTrusted else { return }

        if action.isMultiWindowAction {
            switch action {
            case .tileRows:
                tileAll(mode: .rows)
            case .tileColumns:
                tileAll(mode: .columns)
            case .cycleStacked:
                cycleStacked(backward: false)
            case .cycleStackedBack:
                cycleStacked(backward: true)
            case .restoreLastWorkspace:
                restoreLastWorkspaceHandler?()
            case .stashToggle:
                stashToggleHandler?()
            case .unstashAll:
                unstashAllHandler?()
            default:
                break
            }
            return
        }

        guard let window = focusedAXWindow() else { return }
        if isIgnored(window) { return }
        if shouldReflowPinInstead(of: window) {
            pinModeReflow?()
            return
        }
        apply(action, to: window)
    }

    private func shouldReflowPinInstead(of window: AXUIElement) -> Bool {
        guard UserPreferences.shared.pinModeEnabled,
              let pinID = UserPreferences.shared.pinAppBundleID else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == pinID else { return false }
        return true
    }

    /// Where min-size overflow should go when an app refuses to fit its zone.
    enum ZoneSpill {
        /// Spill left / down (away from right / top neighbors). Use for left & bottom tiles.
        case outwardLow
        /// Spill right / up (away from left / bottom neighbors). Use for right & top tiles.
        case outwardHigh
        /// Keep centered in the zone (center column).
        case center
    }

    /// Places `window` into a Cocoa-space rect on `screen`.
    /// - Parameter activate: When true, raise the window and activate its app (bring to front).
    /// - Parameter clampToZone: Re-fit after place so min-size apps don’t cover siblings
    ///   (e.g. System Settings in a ⅓ column covering Finder).
    func place(
        _ window: ManagedWindow,
        cocoaFrame: CGRect,
        on screen: NSScreen,
        activate: Bool = true,
        clampToZone: Bool = true,
        spill: ZoneSpill = .center
    ) {
        guard AccessibilityPermission.isTrusted else { return }
        if let bundleID = window.appBundleID, UserPreferences.shared.isAppIgnored(bundleID) {
            return
        }

        disableChromeEnhancedUIIfNeeded(pid: window.pid)
        if let currentAX = windowFrame(window.element) {
            rememberFrameIfNeeded(currentAX, for: window.element)
        }
        let aligned = pixelAlign(cocoaFrame)
        let targetAX = ScreenHelper.cocoaToAccessibility(aligned, on: screen)
        prepareWindowForResize(window.element)
        setWindowFrame(window.element, frame: targetAX, verifyAgainst: targetAX)

        if clampToZone {
            enforceWithinZone(window.element, zoneCocoa: aligned, on: screen, spill: spill)
        }

        if activate {
            bringToFront(window)
        }
    }

    /// Raises the AX window and activates its app so it isn’t left behind siblings (e.g. Brave).
    func bringToFront(_ window: ManagedWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Focused AX window (for drag-to-snap).
    func focusedWindowElement() -> AXUIElement? {
        guard AccessibilityPermission.isTrusted else { return nil }
        return focusedAXWindow()
    }

    /// Current window frame in Accessibility coordinates (origin top-left).
    func frameAX(of window: AXUIElement) -> CGRect? {
        windowFrame(window)
    }

    /// Moves / resizes an arbitrary AX window to a Cocoa-space rect.
    func setCocoaFrame(_ window: AXUIElement, cocoaFrame: CGRect, on screen: NSScreen) {
        guard AccessibilityPermission.isTrusted else { return }
        if isIgnored(window) { return }
        disableChromeEnhancedUIIfNeeded(for: window)
        if let currentAX = windowFrame(window) {
            rememberFrameIfNeeded(currentAX, for: window)
        }
        let aligned = pixelAlign(cocoaFrame)
        let targetAX = ScreenHelper.cocoaToAccessibility(aligned, on: screen)
        prepareWindowForResize(window)
        setWindowFrame(window, frame: targetAX, verifyAgainst: targetAX)
    }

    /// Live split-resize path: one fast AX write (no verify/retry) for snappy dragging.
    func setAXFrameLive(_ window: AXUIElement, frame: CGRect) {
        guard AccessibilityPermission.isTrusted else { return }
        if isIgnored(window) { return }
        applyAXFrameFast(window, frame: frame)
    }

    /// Heavier finalize after mouse-up — ensures apps that ignored live writes settle.
    func setAXFrameFinal(_ window: AXUIElement, frame: CGRect) {
        guard AccessibilityPermission.isTrusted else { return }
        if isIgnored(window) { return }
        disableChromeEnhancedUIIfNeeded(for: window)
        setWindowFrame(window, frame: frame, verifyAgainst: frame)
    }

    // MARK: - Snap apply

    private func apply(_ action: SnapAction, to window: AXUIElement) {
        disableChromeEnhancedUIIfNeeded(for: window)

        guard let currentAX = windowFrame(window) else { return }
        let currentCocoa = ScreenHelper.accessibilityToCocoa(currentAX)
        let screen = ScreenHelper.screen(containing: currentCocoa)
        let windowID = windowID(of: window)
        let screenKey = ScreenHelper.screenKey(screen)

        switch action {
        case .restore:
            restoreWindow(window)
            lastSnapAction = nil
            return
        case .center:
            centerKeepingSize(window, currentAX: currentAX, on: screen)
            lastSnapAction = nil
            return
        case .nextDisplay:
            moveToDisplay(window, from: screen, next: true)
            lastSnapAction = nil
            return
        case .previousDisplay:
            moveToDisplay(window, from: screen, next: false)
            lastSnapAction = nil
            return
        case .maximizeHeight:
            rememberFrameIfNeeded(currentAX, for: window)
            maximizeHeight(window, currentAX: currentAX, on: screen)
            lastSnapAction = nil
            return
        case .smaller:
            rememberFrameIfNeeded(currentAX, for: window)
            resizeCentered(window, currentAX: currentAX, on: screen, larger: false)
            lastSnapAction = nil
            return
        case .larger:
            rememberFrameIfNeeded(currentAX, for: window)
            resizeCentered(window, currentAX: currentAX, on: screen, larger: true)
            lastSnapAction = nil
            return
        default:
            break
        }

        // Rectangle-style: same shortcut again → next size in family, then adjacent display.
        if let family = action.sizeCycleFamily,
           shouldAdvanceSizeCycle(
               entry: action,
               family: family,
               windowID: windowID,
               screenKey: screenKey,
               currentAX: currentAX,
               on: screen
           ),
           let currentApplied = cycleAnchor(
               entry: action,
               family: family,
               windowID: windowID,
               screenKey: screenKey,
               currentAX: currentAX,
               on: screen
           ),
           let idx = family.firstIndex(of: currentApplied) {
            let nextIdx = idx + 1
            if nextIdx < family.count {
                applyGeometric(family[nextIdx], to: window, currentAX: currentAX, on: screen, entry: action)
                return
            }
            if action.hasCycleDirection, NSScreen.screens.count > 1 {
                lastSnapAction = nil
                cycleToAdjacentMonitor(window: window, action: currentApplied, from: screen)
                return
            }
            // Wrap within the family when there is no second display.
            applyGeometric(family[0], to: window, currentAX: currentAX, on: screen, entry: action)
            return
        }

        // Quarters / halves without a multi-size family: repeat → next monitor.
        if action.hasCycleDirection, action.sizeCycleFamily == nil {
            if let targetCocoa = action.snappedRect(on: screen) {
                let targetAX = ScreenHelper.cocoaToAccessibility(targetCocoa, on: screen)
                let exactMatch = framesMatch(currentAX, targetAX)
                let repeatMatch = windowID != nil
                    && lastSnapAction?.windowID == windowID
                    && lastSnapAction?.entryAction == action
                    && lastSnapAction?.screenKey == screenKey
                if exactMatch || repeatMatch {
                    lastSnapAction = nil
                    cycleToAdjacentMonitor(window: window, action: action, from: screen)
                    return
                }
            }
        }

        applyGeometric(action, to: window, currentAX: currentAX, on: screen, entry: action)
    }

    private func shouldAdvanceSizeCycle(
        entry: SnapAction,
        family: [SnapAction],
        windowID: String?,
        screenKey: String,
        currentAX: CGRect,
        on screen: NSScreen
    ) -> Bool {
        if let windowID,
           let last = lastSnapAction,
           last.windowID == windowID,
           last.screenKey == screenKey,
           last.entryAction == entry,
           family.contains(last.appliedAction) {
            return true
        }
        // Already sitting on this shortcut's own tile → treat as a repeat.
        if let target = entry.snappedRect(on: screen) {
            let targetAX = ScreenHelper.cocoaToAccessibility(target, on: screen)
            if framesMatch(currentAX, targetAX) {
                return true
            }
        }
        return false
    }

    private func cycleAnchor(
        entry: SnapAction,
        family: [SnapAction],
        windowID: String?,
        screenKey: String,
        currentAX: CGRect,
        on screen: NSScreen
    ) -> SnapAction? {
        if let windowID,
           let last = lastSnapAction,
           last.windowID == windowID,
           last.screenKey == screenKey,
           last.entryAction == entry,
           family.contains(last.appliedAction) {
            return last.appliedAction
        }
        if family.contains(entry),
           let target = entry.snappedRect(on: screen) {
            let targetAX = ScreenHelper.cocoaToAccessibility(target, on: screen)
            if framesMatch(currentAX, targetAX) {
                return entry
            }
        }
        // Prefer the family member that matches the current frame.
        for member in family {
            guard let target = member.snappedRect(on: screen) else { continue }
            let targetAX = ScreenHelper.cocoaToAccessibility(target, on: screen)
            if framesMatch(currentAX, targetAX) {
                return member
            }
        }
        return entry
    }

    private func applyGeometric(
        _ action: SnapAction,
        to window: AXUIElement,
        currentAX: CGRect,
        on screen: NSScreen,
        entry: SnapAction
    ) {
        guard let targetCocoa = action.snappedRect(on: screen) else { return }
        let targetAX = ScreenHelper.cocoaToAccessibility(targetCocoa, on: screen)
        rememberFrameIfNeeded(currentAX, for: window)
        setWindowFrame(window, frame: targetAX)
        if let windowID = windowID(of: window) {
            lastSnapAction = (
                windowID: windowID,
                entryAction: entry,
                appliedAction: action,
                screenKey: ScreenHelper.screenKey(screen)
            )
        }
    }

    private func maximizeHeight(_ window: AXUIElement, currentAX: CGRect, on screen: NSScreen) {
        // Flush to work-area height (no window gap), keep width/x.
        let area = ScreenHelper.workArea(for: screen)
        let cocoa = ScreenHelper.accessibilityToCocoa(currentAX)
        let width = min(max(cocoa.width, 120), area.width)
        let x = min(max(cocoa.origin.x, area.minX), area.maxX - width)
        let targetCocoa = CGRect(x: x, y: area.minY, width: width, height: area.height)
        let targetAX = ScreenHelper.cocoaToAccessibility(pixelAlign(targetCocoa), on: screen)
        if framesMatch(currentAX, targetAX) { return }
        setWindowFrame(window, frame: targetAX)
    }

    /// Grow / shrink about the window center; clamp to the work area.
    private func resizeCentered(
        _ window: AXUIElement,
        currentAX: CGRect,
        on screen: NSScreen,
        larger: Bool
    ) {
        let area = ScreenHelper.workArea(for: screen)
        let cocoa = ScreenHelper.accessibilityToCocoa(currentAX)
        let deltaW = max(floor(area.width * 0.05), 40)
        let deltaH = max(floor(area.height * 0.05), 40)
        let sign: CGFloat = larger ? 1 : -1
        let minW: CGFloat = 200
        let minH: CGFloat = 120
        let newW = min(max(cocoa.width + sign * deltaW, minW), area.width)
        let newH = min(max(cocoa.height + sign * deltaH, minH), area.height)
        if abs(newW - cocoa.width) < 0.5, abs(newH - cocoa.height) < 0.5 { return }

        var newX = cocoa.midX - newW / 2
        var newY = cocoa.midY - newH / 2
        newX = min(max(newX, area.minX), area.maxX - newW)
        newY = min(max(newY, area.minY), area.maxY - newH)

        let targetCocoa = pixelAlign(CGRect(x: newX, y: newY, width: newW, height: newH))
        let targetAX = ScreenHelper.cocoaToAccessibility(targetCocoa, on: screen)
        setWindowFrame(window, frame: targetAX)
    }

    private func centerKeepingSize(_ window: AXUIElement, currentAX: CGRect, on screen: NSScreen) {
        let area = ScreenHelper.workArea(for: screen)
        let size = currentAX.size
        let cocoaCurrent = ScreenHelper.accessibilityToCocoa(currentAX)
        let centeredCocoa = CGRect(
            x: area.minX + (area.width - size.width) / 2,
            y: area.minY + (area.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        // If already centered (tolerance), do nothing.
        if framesMatch(
            ScreenHelper.cocoaToAccessibility(cocoaCurrent, on: screen),
            ScreenHelper.cocoaToAccessibility(centeredCocoa, on: screen)
        ) {
            return
        }
        rememberFrameIfNeeded(currentAX, for: window)
        let targetAX = ScreenHelper.cocoaToAccessibility(centeredCocoa, on: screen)
        // Position only — keep size.
        var position = targetAX.origin
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }

    private func moveToDisplay(_ window: AXUIElement, from current: NSScreen, next: Bool) {
        let target = next
            ? ScreenHelper.nextScreen(from: current)
            : ScreenHelper.previousScreen(from: current)
        guard let screen = target, let currentAX = windowFrame(window) else { return }
        rememberFrameIfNeeded(currentAX, for: window)
        let targetCocoa = ScreenHelper.workArea(for: screen)
        let targetAX = ScreenHelper.cocoaToAccessibility(targetCocoa, on: screen)
        setWindowFrame(window, frame: targetAX)
    }

    private func cycleToAdjacentMonitor(window: AXUIElement, action: SnapAction, from screen: NSScreen) {
        guard NSScreen.screens.count > 1 else { return }
        let targetScreen: NSScreen?
        if action.cycleDirection > 0 {
            targetScreen = ScreenHelper.nextScreen(from: screen)
        } else {
            targetScreen = ScreenHelper.previousScreen(from: screen)
        }
        guard let nextScreen = targetScreen else { return }
        let mirrored = action.mirrored
        guard let targetCocoa = mirrored.snappedRect(on: nextScreen) else { return }
        if let currentAX = windowFrame(window) {
            rememberFrameIfNeeded(currentAX, for: window)
        }
        let targetAX = ScreenHelper.cocoaToAccessibility(targetCocoa, on: nextScreen)
        setWindowFrame(window, frame: targetAX)
        if let windowID = windowID(of: window) {
            // Reset size-cycle: next repeat of the same side starts at the mirrored tile.
            lastSnapAction = (
                windowID: windowID,
                entryAction: mirrored,
                appliedAction: mirrored,
                screenKey: ScreenHelper.screenKey(nextScreen)
            )
        }
    }

    // MARK: - Tile all (rows / columns)

    private func tileAll(mode: TileMode) {
        let screen = screenForMultiWindowAction()
        let area = ScreenHelper.workArea(for: screen)
        let gap = UserPreferences.shared.windowGap
        let pinID = UserPreferences.shared.pinModeEnabled ? UserPreferences.shared.pinAppBundleID : nil

        var windows = listCandidateWindows().compactMap { window -> (ManagedWindow, CGRect)? in
            if let pinID, window.appBundleID == pinID { return nil }
            if isWindowStashed?(window.id) == true { return nil }
            guard let ax = windowFrame(window.element) else { return nil }
            let cocoa = ScreenHelper.accessibilityToCocoa(ax)
            guard ScreenHelper.screen(containing: cocoa) == screen else { return nil }
            return (window, cocoa)
        }

        guard !windows.isEmpty else { return }

        // Order by upper-left before tiling (Rectangle-style).
        windows.sort { a, b in
            if mode == .columns {
                if abs(a.1.minX - b.1.minX) > 8 { return a.1.minX < b.1.minX }
                return a.1.maxY > b.1.maxY
            }
            if abs(a.1.maxY - b.1.maxY) > 8 { return a.1.maxY > b.1.maxY }
            return a.1.minX < b.1.minX
        }

        let signature = windows.map(\.0.id).sorted().joined(separator: "|")
        let screenKey = ScreenHelper.screenKey(screen)
        let layouts = Self.tileGroupLayouts(count: windows.count, maxPerGroup: 3)
        guard !layouts.isEmpty else { return }

        var index = 0
        if let last = lastTileState,
           last.screenKey == screenKey,
           last.mode == mode,
           last.signature == signature {
            index = (last.index + 1) % layouts.count
        }
        lastTileState = (screenKey, mode, index, signature)

        let groups = layouts[index]
        let managed = windows.map(\.0)

        if mode == .columns {
            placeInColumns(managed, groups: groups, area: area, gap: gap, on: screen)
        } else {
            placeInRows(managed, groups: groups, area: area, gap: gap, on: screen)
        }
    }

    /// For `maxPerGroup` 3 and n=6 → [[1,1,1,1,1,1], [2,2,2], [3,3]] (unique balanced splits).
    private static func tileGroupLayouts(count: Int, maxPerGroup: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        var layouts: [[Int]] = []
        var seen = Set<String>()
        let limit = max(1, min(maxPerGroup, count))
        for perGroup in 1...limit {
            let groupCount = Int(ceil(Double(count) / Double(perGroup)))
            let sizes = distribute(count, into: groupCount)
            let key = sizes.map(String.init).joined(separator: ",")
            if seen.insert(key).inserted {
                layouts.append(sizes)
            }
        }
        return layouts
    }

    private static func distribute(_ total: Int, into groups: Int) -> [Int] {
        let g = max(1, groups)
        var sizes = Array(repeating: total / g, count: g)
        let rem = total % g
        for i in 0..<rem {
            sizes[i] += 1
        }
        return sizes.filter { $0 > 0 }
    }

    private func placeInColumns(
        _ windows: [ManagedWindow],
        groups: [Int],
        area: CGRect,
        gap: CGFloat,
        on screen: NSScreen
    ) {
        let cols = groups.count
        guard cols > 0 else { return }
        let colWidth = floor(area.width / CGFloat(cols))
        var index = 0
        for (col, countInCol) in groups.enumerated() {
            let x = area.minX + CGFloat(col) * colWidth
            let width = (col == cols - 1) ? (area.maxX - x) : colWidth
            let rowHeight = floor(area.height / CGFloat(countInCol))
            for row in 0..<countInCol {
                guard index < windows.count else { return }
                let yTop = area.maxY - CGFloat(row) * rowHeight
                let height = (row == countInCol - 1) ? (yTop - area.minY) : rowHeight
                let y = yTop - height
                var rect = CGRect(x: x, y: y, width: width, height: height)
                rect = ScreenHelper.applyWindowGap(rect, gap: gap)
                place(windows[index], cocoaFrame: rect, on: screen, activate: index == 0, clampToZone: true, spill: .center)
                index += 1
            }
        }
    }

    private func placeInRows(
        _ windows: [ManagedWindow],
        groups: [Int],
        area: CGRect,
        gap: CGFloat,
        on screen: NSScreen
    ) {
        let rows = groups.count
        guard rows > 0 else { return }
        let rowHeight = floor(area.height / CGFloat(rows))
        var index = 0
        for (row, countInRow) in groups.enumerated() {
            let yTop = area.maxY - CGFloat(row) * rowHeight
            let height = (row == rows - 1) ? (yTop - area.minY) : rowHeight
            let y = yTop - height
            let colWidth = floor(area.width / CGFloat(countInRow))
            for col in 0..<countInRow {
                guard index < windows.count else { return }
                let x = area.minX + CGFloat(col) * colWidth
                let width = (col == countInRow - 1) ? (area.maxX - x) : colWidth
                var rect = CGRect(x: x, y: y, width: width, height: height)
                rect = ScreenHelper.applyWindowGap(rect, gap: gap)
                place(windows[index], cocoaFrame: rect, on: screen, activate: index == 0, clampToZone: true, spill: .center)
                index += 1
            }
        }
    }

    // MARK: - Cycle stacked windows

    private func cycleStacked(backward: Bool) {
        guard let focused = focusedManagedWindow(),
              let focusedAX = windowFrame(focused.element) else {
            NSSound.beep()
            return
        }
        let focusedCocoa = ScreenHelper.accessibilityToCocoa(focusedAX)
        let screen = ScreenHelper.screen(containing: focusedCocoa)
        let pinID = UserPreferences.shared.pinModeEnabled ? UserPreferences.shared.pinAppBundleID : nil

        let stack = listCandidateWindows().compactMap { window -> ManagedWindow? in
            if let pinID, window.appBundleID == pinID { return nil }
            guard let ax = windowFrame(window.element) else { return nil }
            let cocoa = ScreenHelper.accessibilityToCocoa(ax)
            guard ScreenHelper.screen(containing: cocoa) == screen else { return nil }
            let sameOrigin = abs(cocoa.minX - focusedCocoa.minX) < 36
                && abs(cocoa.minY - focusedCocoa.minY) < 36
            let sameSize = abs(cocoa.width - focusedCocoa.width) < 24
                && abs(cocoa.height - focusedCocoa.height) < 24
            return (sameOrigin && sameSize) ? window : nil
        }

        guard stack.count >= 2 else {
            NSSound.beep()
            return
        }

        let ordered = orderFrontToBack(stack)
        if backward {
            if ordered.count > 1 {
                bringToFront(ordered[1])
            }
        } else if let back = ordered.last {
            bringToFront(back)
        }
    }

    /// Front-most first, using CGWindowList z-order when possible.
    private func orderFrontToBack(_ windows: [ManagedWindow]) -> [ManagedWindow] {
        let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        var rank: [String: Int] = [:]
        for (z, info) in infos.enumerated() {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 40, height > 40 else { continue }
            let quartz = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: width,
                height: height
            )
            for window in windows where window.pid == pid {
                guard let ax = windowFrame(window.element) else { continue }
                // AX frames are already top-left (Quartz-like) globally.
                if framesMatch(ax, quartz, tolerance: 40) {
                    if rank[window.id] == nil {
                        rank[window.id] = z
                    }
                }
            }
        }

        return windows.sorted { a, b in
            let ra = rank[a.id] ?? Int.max
            let rb = rank[b.id] ?? Int.max
            if ra != rb { return ra < rb }
            return a.id < b.id
        }
    }

    private func screenForMultiWindowAction() -> NSScreen {
        if let focused = focusedManagedWindow(),
           let ax = windowFrame(focused.element) {
            return ScreenHelper.screen(containing: ScreenHelper.accessibilityToCocoa(ax))
        }
        let mouse = NSEvent.mouseLocation
        return ScreenHelper.screen(containing: CGRect(origin: mouse, size: CGSize(width: 1, height: 1)))
    }

    // MARK: - Restore

    private func restoreWindow(_ window: AXUIElement) {
        guard let id = windowID(of: window),
              let previous = frameHistory.frame(for: id) else { return }
        setWindowFrame(window, frame: previous)
        frameHistory.forget(windowID: id)
    }

    private func rememberFrameIfNeeded(_ frame: CGRect, for window: AXUIElement) {
        guard let id = windowID(of: window) else { return }
        frameHistory.remember(frame, for: id)
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 15) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance
            && abs(a.origin.y - b.origin.y) < tolerance
            && abs(a.width - b.width) < tolerance
            && abs(a.height - b.height) < tolerance
    }

    // MARK: - Ignored apps

    private func isIgnored(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else {
            return false
        }
        return UserPreferences.shared.isAppIgnored(bundleID)
    }

    // MARK: - Focused managed / candidates

    /// Focused window as a managed candidate (captured before UI steals focus).
    func focusedManagedWindow() -> ManagedWindow? {
        guard AccessibilityPermission.isTrusted else { return nil }
        guard let ax = focusedAXWindow() else { return nil }
        return makeManagedWindow(from: ax)
    }

    /// Visible, non-minimized, resizable windows suitable for layout filling.
    func listCandidateWindows(excludingOwnPID ownPID: pid_t = getpid()) -> [ManagedWindow] {
        guard AccessibilityPermission.isTrusted else { return [] }

        var results: [ManagedWindow] = []
        let running = NSWorkspace.shared.runningApplications

        for app in running {
            // Skip ourselves, background-only agents, and terminated apps.
            if app.processIdentifier == ownPID { continue }
            if app.activationPolicy == .prohibited { continue }
            if app.isTerminated { continue }
            if let bundleID = app.bundleIdentifier, UserPreferences.shared.isAppIgnored(bundleID) {
                continue
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                guard isUsableCandidate(axWindow) else { continue }
                if let managed = makeManagedWindow(from: axWindow, app: app) {
                    results.append(managed)
                }
            }
        }

        // Prefer frontmost app windows first, then by title.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return results.sorted { a, b in
            if a.pid == frontPID && b.pid != frontPID { return true }
            if b.pid == frontPID && a.pid != frontPID { return false }
            return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        }
    }

    // MARK: - Focused window

    private func focusedAXWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        ) == .success,
              let focusedApp = focusedAppRef else {
            return fallbackFrontmostWindow()
        }

        let app = focusedApp as! AXUIElement

        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success,
           let focusedWindow = focusedWindowRef {
            return (focusedWindow as! AXUIElement)
        }

        // Some apps expose windows but not a focused window attribute.
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
           let windows = windowsRef as? [AXUIElement],
           let first = windows.first {
            return first
        }

        return fallbackFrontmostWindow()
    }

    /// Fallback for apps that don't expose a focused AX window.
    private func fallbackFrontmostWindow() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
           let windows = windowsRef as? [AXUIElement],
           let first = windows.first {
            return first
        }

        return nil
    }

    // MARK: - Candidate helpers

    private func isUsableCandidate(_ window: AXUIElement) -> Bool {
        // Minimized?
        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let minimized = minimizedRef as? Bool,
           minimized {
            return false
        }

        // Must have a real frame.
        guard let frame = windowFrame(window), frame.width > 40, frame.height > 40 else {
            return false
        }

        // Prefer resizable windows; if attribute missing, still allow.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
           !settable.boolValue {
            return false
        }

        return true
    }

    private func makeManagedWindow(from window: AXUIElement, app: NSRunningApplication? = nil) -> ManagedWindow? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != 0 else { return nil }

        let running = app ?? NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
        let appName = running?.localizedName ?? "App"
        let bundleID = running?.bundleIdentifier
        let icon = running?.icon

        var titleRef: CFTypeRef?
        var title = ""
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleString = titleRef as? String {
            title = titleString
        }

        // Stable across moves/resizes — frame-based IDs broke "already assigned" filtering
        // after the first layout placement, and could empty/dupe the candidate list.
        let id = windowID(of: window) ?? "\(pid)-ax-\(CFHash(window))"
        return ManagedWindow(
            id: id,
            element: window,
            pid: pid,
            title: title,
            appName: appName,
            appBundleID: bundleID,
            appIcon: icon
        )
    }

    // MARK: - Window ID / frame get-set

    private func windowID(of window: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        guard let position = windowFrame(window)?.origin else {
            return "\(pid)-ax-\(CFHash(window))"
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windowList {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t, wPid == pid,
                  let wNumber = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let wX = bounds["X"] ?? 0
            let wY = bounds["Y"] ?? 0
            if abs(wX - position.x) < 5 && abs(wY - position.y) < 5 {
                return "\(pid)-\(wNumber)"
            }
        }
        return "\(pid)-ax-\(CFHash(window))"
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect, verifyAgainst expected: CGRect? = nil) {
        applyAXFrame(window, frame: frame)

        // Stubborn apps (App Store, browsers, Xcode) often ignore the first pass
        // when previously fullscreen / zoomed / Stage-Manager tiled.
        guard let expected, !frameApproximately(window, matches: expected) else { return }

        applyAXFrame(window, frame: expected)
        guard !frameApproximately(window, matches: expected) else { return }

        // Break sticky zoom with a 1px nudge — NOT a large shrink.
        // A −40px intermediate size opened a visible gap next to neighbors
        // (“aralık açılıp kapanıyor”) before the final expand.
        var nudged = expected
        nudged.size.width = max(200, expected.width - 1)
        nudged.size.height = max(160, expected.height - 1)
        applyAXFrame(window, frame: nudged)
        applyAXFrame(window, frame: expected)

        // One deferred retry after WindowServer settles (fullscreen exit, Electron).
        // Keep the final size only — no second visible shrink.
        let target = expected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            if !self.frameApproximately(window, matches: target) {
                self.applyAXFrame(window, frame: target)
            }
        }
    }

    private func applyAXFrame(_ window: AXUIElement, frame: CGRect) {
        var position = frame.origin
        var size = frame.size

        // Position → size → position → size. Order matters for AppKit apps that clamp.
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Minimal writes for live split dragging — keeps the trailing window responsive.
    private func applyAXFrameFast(_ window: AXUIElement, frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }

    /// Exit fullscreen that blocks half-screen layouts (common with browsers / App Store).
    private func prepareWindowForResize(_ window: AXUIElement) {
        var fullScreenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenRef) == .success,
           let isFullScreen = fullScreenRef as? Bool,
           isFullScreen {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            // Give WindowServer a beat to leave Space/fullscreen before AX size writes.
            usleep(180_000)
        }
    }

    private func frameApproximately(_ window: AXUIElement, matches expected: CGRect, tolerance: CGFloat = 48) -> Bool {
        guard let actual = windowFrame(window) else { return false }
        return abs(actual.origin.x - expected.origin.x) <= tolerance
            && abs(actual.origin.y - expected.origin.y) <= tolerance
            && abs(actual.size.width - expected.width) <= tolerance
            && abs(actual.size.height - expected.height) <= tolerance
    }

    private func pixelAlign(_ rect: CGRect) -> CGRect {
        let x = floor(rect.origin.x)
        let y = floor(rect.origin.y)
        let maxX = floor(rect.origin.x + rect.size.width)
        let maxY = floor(rect.origin.y + rect.size.height)
        return CGRect(x: x, y: y, width: max(1, maxX - x), height: max(1, maxY - y))
    }

    /// If the app ignored our size (min height/width), pin so overflow goes *outward*
    /// (off the screen edge) instead of covering the neighboring column/row.
    private func enforceWithinZone(
        _ window: AXUIElement,
        zoneCocoa: CGRect,
        on screen: NSScreen,
        spill: ZoneSpill
    ) {
        guard let actualAX = windowFrame(window) else { return }
        var cocoa = ScreenHelper.accessibilityToCocoa(actualAX)
        let zone = zoneCocoa

        let spills =
            cocoa.minX < zone.minX - 2
            || cocoa.maxX > zone.maxX + 2
            || cocoa.minY < zone.minY - 2
            || cocoa.maxY > zone.maxY + 2
            || cocoa.width > zone.width + 2
            || cocoa.height > zone.height + 2

        guard spills else { return }

        // Force exact zone size first (apps often accept a second, firmer write).
        let forcedAX = ScreenHelper.cocoaToAccessibility(zone, on: screen)
        applyAXFrame(window, frame: forcedAX)

        if let again = windowFrame(window) {
            cocoa = ScreenHelper.accessibilityToCocoa(again)
        }

        let stillWide = cocoa.width > zone.width + 2
        let stillTall = cocoa.height > zone.height + 2
        guard stillWide || stillTall
            || cocoa.minX < zone.minX - 2 || cocoa.maxX > zone.maxX + 2
            || cocoa.minY < zone.minY - 2 || cocoa.maxY > zone.maxY + 2
        else { return }

        var fixed = cocoa
        // Prefer keeping full app chrome visible; only force size when we must.
        if stillTall {
            fixed.size.height = min(fixed.height, zone.height)
        }
        if stillWide {
            // Try forced width once more; many apps accept after a nudge.
            fixed.size.width = zone.width
        }

        switch spill {
        case .outwardLow:
            // Left / bottom tile: keep the *inner* seam clear (zone.maxX / zone.maxY).
            fixed.origin.x = zone.maxX - fixed.width
            fixed.origin.y = zone.minY
            if fixed.height > zone.height {
                fixed.size.height = zone.height
            }
        case .outwardHigh:
            // Right / top tile: keep the *inner* seam clear (zone.minX / zone.minY).
            fixed.origin.x = zone.minX
            fixed.origin.y = zone.maxY - fixed.height
            if fixed.height > zone.height {
                fixed.size.height = zone.height
                fixed.origin.y = zone.minY
            }
        case .center:
            fixed.origin.x = zone.midX - fixed.width / 2
            fixed.origin.y = zone.midY - fixed.height / 2
            // Soft clamp so center doesn’t eat the whole screen.
            if fixed.width > zone.width {
                fixed.size.width = zone.width
                fixed.origin.x = zone.minX
            }
            if fixed.height > zone.height {
                fixed.size.height = zone.height
                fixed.origin.y = zone.minY
            }
        }

        // Full-height tiles should always use the zone height.
        fixed.size.height = zone.height
        if spill == .outwardHigh && stillTall {
            fixed.origin.y = zone.minY
        } else if spill == .outwardLow {
            fixed.origin.y = zone.minY
        }

        let clampAX = ScreenHelper.cocoaToAccessibility(pixelAlign(fixed), on: screen)
        applyAXFrame(window, frame: clampAX)
    }

    /// Chrome enables AXEnhancedUserInterface which animates AX moves; disable per-move.
    private func disableChromeEnhancedUIIfNeeded(for window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        if pid != 0 {
            disableChromeEnhancedUIIfNeeded(pid: pid)
            return
        }

        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            disableChromeEnhancedUIIfNeeded(pid: frontPID)
        }
    }

    private func disableChromeEnhancedUIIfNeeded(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanFalse
        )
    }
}
