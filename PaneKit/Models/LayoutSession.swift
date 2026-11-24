import AppKit
import Foundation

/// Tracks zone → window assignments while the user fills a layout.
final class LayoutSession {
    let template: LayoutTemplate
    let screen: NSScreen
    /// Window that was focused when the layout picker opened.
    let focusedWindow: ManagedWindow?

    /// zoneId → assigned window
    private(set) var assignments: [String: ManagedWindow] = [:]
    /// Zone waiting for a candidate pick (after first placement).
    private(set) var pendingZoneID: String?
    /// Per-zone fill factor inside the template rect (1 = full zone). Used by −/+ size controls.
    private(set) var zoneScales: [String: CGFloat] = [:]

    init(template: LayoutTemplate, screen: NSScreen, focusedWindow: ManagedWindow?) {
        self.template = template
        self.screen = screen
        self.focusedWindow = focusedWindow
    }

    var emptyZones: [LayoutZone] {
        template.zones.filter { assignments[$0.id] == nil }
    }

    var isComplete: Bool {
        emptyZones.isEmpty
    }

    var hasPlacedFirst: Bool {
        !assignments.isEmpty
    }

    func window(in zoneID: String) -> ManagedWindow? {
        assignments[zoneID]
    }

    func isAssigned(_ window: ManagedWindow) -> Bool {
        assignments.values.contains { assigned in
            if assigned.id == window.id { return true }
            if assigned.pid == window.pid && CFEqual(assigned.element, window.element) {
                return true
            }
            return false
        }
    }

    @discardableResult
    func assign(_ window: ManagedWindow, to zoneID: String) -> Bool {
        guard template.zones.contains(where: { $0.id == zoneID }) else { return false }
        // Remove prior assignment of this window if any.
        for (existingZone, existing) in assignments where existing.id == window.id
            || (existing.pid == window.pid && CFEqual(existing.element, window.element)) {
            assignments.removeValue(forKey: existingZone)
        }
        assignments[zoneID] = window
        if zoneScales[zoneID] == nil {
            zoneScales[zoneID] = 1
        }
        if pendingZoneID == zoneID {
            pendingZoneID = nil
        }
        return true
    }

    func selectPendingZone(_ zoneID: String?) {
        guard let zoneID else {
            pendingZoneID = nil
            return
        }
        // Allow empty or already-filled zones (reassign while panel is open).
        guard template.zones.contains(where: { $0.id == zoneID }) else { return }
        pendingZoneID = zoneID
    }

    /// Shrink (−0.1) or grow (+0.1) the window inside its zone. Returns new scale or nil.
    @discardableResult
    func adjustScale(for zoneID: String, delta: CGFloat) -> CGFloat? {
        guard assignments[zoneID] != nil else { return nil }
        let current = zoneScales[zoneID] ?? 1
        let next = min(1, max(0.45, current + delta))
        zoneScales[zoneID] = next
        return next
    }

    func absoluteRect(for zone: LayoutZone) -> CGRect {
        let area = ScreenHelper.workArea(for: screen)
        let frames = template.zoneFrames(in: area)
        var full = frames[zone.id] ?? zone.absoluteRect(in: area)
        full = ScreenHelper.applyWindowGap(full, gap: UserPreferences.shared.windowGap)
        let scale = zoneScales[zone.id] ?? 1
        guard scale < 0.999 else { return full }
        let width = full.width * scale
        let height = full.height * scale
        // Keep top-left of the zone so multi-window layouts stay predictable.
        return CGRect(
            x: full.minX,
            y: full.maxY - height,
            width: width,
            height: height
        )
    }
}
