import AppKit

enum ScreenHelper {
    /// Usable tiling area: visibleFrame minus Stage Manager strip and Pin sidebar.
    /// Window gap is applied per-tile via `applyWindowGap`, not here.
    static func workArea(for screen: NSScreen) -> CGRect {
        var area = screen.visibleFrame
        let prefs = UserPreferences.shared

        if prefs.stageManagerInsetEnabled,
           isPrimaryScreen(screen),
           isStageManagerEnabled {
            let strip = max(0, prefs.stageManagerWidth)
            if strip > 0, area.width > strip + 80 {
                area.origin.x += strip
                area.size.width -= strip
            }
        }

        if prefs.pinModeEnabled,
           prefs.pinAppBundleID != nil,
           isPrimaryScreen(screen) {
            let sidebar = max(0, prefs.pinSidebarWidth)
            if sidebar > 0, area.width > sidebar + 80 {
                area.size.width -= sidebar
            }
        }

        return area
    }

    /// Inset a tile by `gap/2` on each side so neighbors share a full `gap` between them.
    static func applyWindowGap(_ rect: CGRect, gap: CGFloat) -> CGRect {
        let g = max(0, gap)
        guard g > 0.5 else { return rect }
        let inset = g / 2
        let result = rect.insetBy(dx: inset, dy: inset)
        guard result.width >= 80, result.height >= 60 else { return rect }
        return result
    }

    /// Right-side Pin sidebar on the primary display (full visible height), with gap applied.
    static func pinSidebarFrame(on screen: NSScreen) -> CGRect? {
        let prefs = UserPreferences.shared
        guard prefs.pinModeEnabled, prefs.pinAppBundleID != nil else { return nil }
        guard isPrimaryScreen(screen) else { return nil }
        let visible = screen.visibleFrame
        let width = min(max(prefs.pinSidebarWidth, 200), visible.width * 0.5)
        let raw = CGRect(
            x: visible.maxX - width,
            y: visible.minY,
            width: width,
            height: visible.height
        )
        return applyWindowGap(raw, gap: prefs.windowGap)
    }

    static func isPrimaryScreen(_ screen: NSScreen) -> Bool {
        guard let main = NSScreen.main else { return screen == NSScreen.screens.first }
        return screen == main
    }

    /// Best-effort Stage Manager detection (macOS Ventura+).
    static var isStageManagerEnabled: Bool {
        let wm = UserDefaults(suiteName: "com.apple.WindowManager")
        if wm?.object(forKey: "GloballyEnabled") != nil {
            return wm?.bool(forKey: "GloballyEnabled") ?? false
        }
        // Older keys / fallbacks seen across macOS versions.
        if wm?.object(forKey: "StageManagerEnabled") != nil {
            return wm?.bool(forKey: "StageManagerEnabled") ?? false
        }
        return false
    }

    /// Screen that contains the largest intersection with `rect` (Cocoa coords).
    static func screen(containing rect: CGRect) -> NSScreen {
        var best = NSScreen.main ?? NSScreen.screens[0]
        var bestArea: CGFloat = 0

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    /// Screens sorted left-to-right (then top-to-bottom) for display moves.
    static var sortedScreens: [NSScreen] {
        NSScreen.screens.sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.frame.maxY > $1.frame.maxY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    /// Next screen to the right (by physical position). No wrap.
    static func nextScreen(from current: NSScreen) -> NSScreen? {
        let screens = sortedScreens
        guard screens.count > 1, let idx = screens.firstIndex(of: current) else { return nil }
        let nextIdx = idx + 1
        guard nextIdx < screens.count else { return nil }
        return screens[nextIdx]
    }

    /// Previous screen to the left (by physical position). No wrap.
    static func previousScreen(from current: NSScreen) -> NSScreen? {
        let screens = sortedScreens
        guard screens.count > 1, let idx = screens.firstIndex(of: current) else { return nil }
        let prevIdx = idx - 1
        guard prevIdx >= 0 else { return nil }
        return screens[prevIdx]
    }

    /// Stable-ish identity for comparing “same screen” across a snap cycle.
    static func screenKey(_ screen: NSScreen) -> String {
        "\(Int(screen.frame.minX)),\(Int(screen.frame.minY)),\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    /// Convert a Cocoa-space rect (origin bottom-left) to Accessibility space (origin top-left).
    static func cocoaToAccessibility(_ rect: CGRect, on screen: NSScreen) -> CGRect {
        // Global Cocoa Y grows upward from the bottom of the primary display area.
        // AX uses top-left of the primary display as origin, Y growing downward.
        let primaryHeight = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        let axY = primaryHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: axY, width: rect.width, height: rect.height)
    }

    /// Convert an Accessibility-space rect to Cocoa space.
    static func accessibilityToCocoa(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let cocoaY = primaryHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }

    /// Convert a Quartz / CGEvent point (origin top-left, Y down) to Cocoa (Y up).
    static func quartzPointToCocoa(_ point: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
