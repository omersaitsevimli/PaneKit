import Foundation
import ServiceManagement

/// UserDefaults-backed preferences for PaneKit.
final class UserPreferences {
    static let shared = UserPreferences()

    /// Preset magnet / snap-zone thicknesses (points). Default is deliberately narrow.
    static let snapZoneThicknessPresets: [CGFloat] = [4, 6, 8, 12, 24]
    static let defaultSnapZoneThickness: CGFloat = 6

    /// Almost-maximize inset presets (points from each edge).
    static let almostMaximizeInsetPresets: [CGFloat] = [10, 20, 40, 60]
    static let defaultAlmostMaximizeInset: CGFloat = 20

    /// Gap between snapped windows (full gap; each tile insets by half).
    static let windowGapPresets: [CGFloat] = [0, 4, 8, 12, 16]
    static let defaultWindowGap: CGFloat = 0

    static let pinSidebarWidthPresets: [CGFloat] = [300, 400, 500]
    static let defaultPinSidebarWidth: CGFloat = 400
    static let defaultStageManagerWidth: CGFloat = 190

    private enum Key {
        static let dragSnapEnabled = "dragSnapEnabled"
        static let splitResizeEnabled = "splitResizeEnabled"
        static let optionGreenButtonLayoutsEnabled = "optionGreenButtonLayoutsEnabled"
        static let snapZoneThickness = "snapZoneThickness"
        static let almostMaximizeInset = "almostMaximizeInset"
        static let windowGap = "windowGap"
        static let stageManagerInsetEnabled = "stageManagerInsetEnabled"
        static let stageManagerWidth = "stageManagerWidth"
        static let pinModeEnabled = "pinModeEnabled"
        static let pinAppBundleID = "pinAppBundleID"
        static let pinAppName = "pinAppName"
        static let pinSidebarWidth = "pinSidebarWidth"
        static let workspaces = "workspaces"
        static let lastWorkspaceID = "lastWorkspaceID"
        static let displayConnectWorkspaceID = "displayConnectWorkspaceID"
        static let restoreWorkspaceOnDisplayConnect = "restoreWorkspaceOnDisplayConnect"
        static let stashEdgeRevealEnabled = "stashEdgeRevealEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let customShortcuts = "customShortcuts"
        static let ignoredApps = "ignoredApps"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Drag snap

    /// When false, drag-to-edge snapping is fully off (keyboard/menu snap still works).
    var dragSnapEnabled: Bool {
        get {
            if defaults.object(forKey: Key.dragSnapEnabled) == nil { return true }
            return defaults.bool(forKey: Key.dragSnapEnabled)
        }
        set { defaults.set(newValue, forKey: Key.dragSnapEnabled) }
    }

    /// Edge magnet thickness in points. Narrow default (6) avoids fighting screenshots / selection.
    var snapZoneThickness: CGFloat {
        get {
            let raw = defaults.object(forKey: Key.snapZoneThickness) as? Double
            let value = CGFloat(raw ?? Double(Self.defaultSnapZoneThickness))
            return min(max(value, 2), 48)
        }
        set {
            let clamped = min(max(newValue, 2), 48)
            defaults.set(Double(clamped), forKey: Key.snapZoneThickness)
        }
    }

    /// Corner hit radius scales with edge thickness (kept deliberately tight).
    var snapCornerRadius: CGFloat {
        max(snapZoneThickness * 4, 20)
    }

    // MARK: - Split resize (drag shared edge)

    /// Drag the seam between two touching windows to grow one / shrink the other.
    var splitResizeEnabled: Bool {
        get {
            if defaults.object(forKey: Key.splitResizeEnabled) == nil { return true }
            return defaults.bool(forKey: Key.splitResizeEnabled)
        }
        set { defaults.set(newValue, forKey: Key.splitResizeEnabled) }
    }

    /// Hover the green zoom button and press ⌥ to open Layouts (Windows-like, less fragile than hover-only).
    var optionGreenButtonLayoutsEnabled: Bool {
        get {
            if defaults.object(forKey: Key.optionGreenButtonLayoutsEnabled) == nil { return true }
            return defaults.bool(forKey: Key.optionGreenButtonLayoutsEnabled)
        }
        set { defaults.set(newValue, forKey: Key.optionGreenButtonLayoutsEnabled) }
    }

    // MARK: - Almost maximize

    var almostMaximizeInset: CGFloat {
        get {
            let raw = defaults.object(forKey: Key.almostMaximizeInset) as? Double
            let value = CGFloat(raw ?? Double(Self.defaultAlmostMaximizeInset))
            return min(max(value, 0), 120)
        }
        set {
            defaults.set(Double(min(max(newValue, 0), 120)), forKey: Key.almostMaximizeInset)
        }
    }

    // MARK: - Window gap / Stage Manager / Pin

    var windowGap: CGFloat {
        get {
            let raw = defaults.object(forKey: Key.windowGap) as? Double
            let value = CGFloat(raw ?? Double(Self.defaultWindowGap))
            return min(max(value, 0), 40)
        }
        set {
            defaults.set(Double(min(max(newValue, 0), 40)), forKey: Key.windowGap)
        }
    }

    var stageManagerInsetEnabled: Bool {
        get {
            if defaults.object(forKey: Key.stageManagerInsetEnabled) == nil { return true }
            return defaults.bool(forKey: Key.stageManagerInsetEnabled)
        }
        set { defaults.set(newValue, forKey: Key.stageManagerInsetEnabled) }
    }

    var stageManagerWidth: CGFloat {
        get {
            let raw = defaults.object(forKey: Key.stageManagerWidth) as? Double
            let value = CGFloat(raw ?? Double(Self.defaultStageManagerWidth))
            return min(max(value, 80), 400)
        }
        set {
            defaults.set(Double(min(max(newValue, 80), 400)), forKey: Key.stageManagerWidth)
        }
    }

    var pinModeEnabled: Bool {
        get { defaults.bool(forKey: Key.pinModeEnabled) }
        set { defaults.set(newValue, forKey: Key.pinModeEnabled) }
    }

    var pinAppBundleID: String? {
        get { defaults.string(forKey: Key.pinAppBundleID) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Key.pinAppBundleID)
            } else {
                defaults.removeObject(forKey: Key.pinAppBundleID)
            }
        }
    }

    var pinAppName: String {
        get { defaults.string(forKey: Key.pinAppName) ?? "App" }
        set { defaults.set(newValue, forKey: Key.pinAppName) }
    }

    var pinSidebarWidth: CGFloat {
        get {
            let raw = defaults.object(forKey: Key.pinSidebarWidth) as? Double
            let value = CGFloat(raw ?? Double(Self.defaultPinSidebarWidth))
            return min(max(value, 200), 800)
        }
        set {
            defaults.set(Double(min(max(newValue, 200), 800)), forKey: Key.pinSidebarWidth)
        }
    }

    // MARK: - Workspaces

    var workspaces: [Workspace] {
        get {
            guard let data = defaults.data(forKey: Key.workspaces),
                  let decoded = try? JSONDecoder().decode([Workspace].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.workspaces)
            }
        }
    }

    var lastWorkspaceID: String? {
        get { defaults.string(forKey: Key.lastWorkspaceID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastWorkspaceID)
            } else {
                defaults.removeObject(forKey: Key.lastWorkspaceID)
            }
        }
    }

    var displayConnectWorkspaceID: String? {
        get { defaults.string(forKey: Key.displayConnectWorkspaceID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.displayConnectWorkspaceID)
            } else {
                defaults.removeObject(forKey: Key.displayConnectWorkspaceID)
            }
        }
    }

    var restoreWorkspaceOnDisplayConnect: Bool {
        get {
            if defaults.object(forKey: Key.restoreWorkspaceOnDisplayConnect) == nil { return true }
            return defaults.bool(forKey: Key.restoreWorkspaceOnDisplayConnect)
        }
        set { defaults.set(newValue, forKey: Key.restoreWorkspaceOnDisplayConnect) }
    }

    /// When true, moving the cursor onto a stashed peek strip reveals the window.
    var stashEdgeRevealEnabled: Bool {
        get {
            if defaults.object(forKey: Key.stashEdgeRevealEnabled) == nil { return true }
            return defaults.bool(forKey: Key.stashEdgeRevealEnabled)
        }
        set { defaults.set(newValue, forKey: Key.stashEdgeRevealEnabled) }
    }

    // MARK: - Launch at login

    var launchAtLoginPreference: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// Current SMAppService status mirrored into a checkbox-friendly bool.
    var isLaunchAtLoginEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) throws -> SMAppService.Status {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        let status = SMAppService.mainApp.status
        launchAtLoginPreference = (status == .enabled || status == .requiresApproval)
        return status
    }

    // MARK: - Custom hotkeys

    func customHotkey(for action: SnapAction) -> (modifiers: UInt32, keyCode: UInt32)? {
        guard let dict = defaults.dictionary(forKey: Key.customShortcuts) as? [String: [String: UInt32]],
              let entry = dict[action.rawValue],
              let modifiers = entry["modifiers"],
              let keyCode = entry["keyCode"] else {
            return nil
        }
        return (modifiers, keyCode)
    }

    func setCustomHotkey(for action: SnapAction, modifiers: UInt32, keyCode: UInt32) {
        var dict = defaults.dictionary(forKey: Key.customShortcuts) as? [String: [String: UInt32]] ?? [:]
        dict[action.rawValue] = ["modifiers": modifiers, "keyCode": keyCode]
        defaults.set(dict, forKey: Key.customShortcuts)
    }

    func disableHotkey(for action: SnapAction) {
        setCustomHotkey(for: action, modifiers: 0, keyCode: 0)
    }

    func resetHotkey(for action: SnapAction) {
        var dict = defaults.dictionary(forKey: Key.customShortcuts) as? [String: [String: UInt32]] ?? [:]
        dict.removeValue(forKey: action.rawValue)
        defaults.set(dict, forKey: Key.customShortcuts)
    }

    func hotkey(for action: SnapAction) -> (modifiers: UInt32, keyCode: UInt32) {
        customHotkey(for: action) ?? action.defaultHotkey
    }

    // MARK: - Ignored apps

    var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? [] }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    func isAppIgnored(_ bundleID: String) -> Bool {
        ignoredApps.contains(bundleID)
    }

    func addIgnoredApp(_ bundleID: String) {
        var list = ignoredApps
        if !list.contains(bundleID) {
            list.append(bundleID)
            ignoredApps = list
        }
    }

    func removeIgnoredApp(_ bundleID: String) {
        ignoredApps = ignoredApps.filter { $0 != bundleID }
    }
}
