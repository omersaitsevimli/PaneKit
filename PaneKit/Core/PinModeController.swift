import AppKit
import ApplicationServices

/// Rectangle-style Todo / Pin mode: keep one app in a right sidebar on the primary display.
final class PinModeController {
    private let windowManager: WindowManager

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    var isEnabled: Bool {
        UserPreferences.shared.pinModeEnabled && UserPreferences.shared.pinAppBundleID != nil
    }

    func setPinApp(bundleID: String, name: String) {
        guard !UserPreferences.shared.isAppIgnored(bundleID) else { return }
        UserPreferences.shared.pinAppBundleID = bundleID
        UserPreferences.shared.pinAppName = name
        if UserPreferences.shared.pinModeEnabled {
            reflow()
        }
    }

    func clearPinApp() {
        UserPreferences.shared.pinAppBundleID = nil
        UserPreferences.shared.pinModeEnabled = false
    }

    @discardableResult
    func setPinModeEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard UserPreferences.shared.pinAppBundleID != nil else { return false }
            UserPreferences.shared.pinModeEnabled = true
            reflow()
            return true
        }
        UserPreferences.shared.pinModeEnabled = false
        return true
    }

    /// Place the pin app's frontmost usable window into the right sidebar.
    func reflow() {
        guard AccessibilityPermission.isTrusted else { return }
        guard UserPreferences.shared.pinModeEnabled,
              let bundleID = UserPreferences.shared.pinAppBundleID else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let frame = ScreenHelper.pinSidebarFrame(on: screen) else { return }
        guard let window = pinWindow(bundleID: bundleID) else { return }
        windowManager.setCocoaFrame(window.element, cocoaFrame: frame, on: screen)
        windowManager.bringToFront(window)
    }

    /// True when the focused window belongs to the pin app (snaps should reflow instead).
    func isPinAppFocused() -> Bool {
        guard isEnabled, let bundleID = UserPreferences.shared.pinAppBundleID else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return front == bundleID
    }

    private func pinWindow(bundleID: String) -> ManagedWindow? {
        let candidates = windowManager.listCandidateWindows().filter { $0.appBundleID == bundleID }
        if let frontPID = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?
            .processIdentifier {
            if let focused = candidates.first(where: { $0.pid == frontPID }) {
                return focused
            }
        }
        return candidates.first
    }
}
