import ApplicationServices
import AppKit
import Foundation

/// Accessibility (TCC) trust helpers.
///
/// Prefer System Settings deep link. Never call
/// `AXIsProcessTrustedWithOptions(prompt: true)` — that modal
/// (“Aygıt Denetimi ve Veri Erişimi”) reappears after every ad-hoc rebuild
/// because TCC keys off CDHash. Stable local signing + Settings toggle sticks.
enum AccessibilityPermission {
    private static let defaults = UserDefaults.standard
    /// Last binary identity for which we already opened System Settings.
    private static let openedSettingsIdentityKey = "ax.openedSettingsIdentity"

    /// Recommended install path (TCC should point at this bundle only).
    static let recommendedAppPath =
        (NSHomeDirectory() as NSString).appendingPathComponent("Applications/PaneKit.app")

    /// True after we already opened Settings (or showed guidance) this process.
    private static var didGuideThisSession = false

    /// Absolute path of the running binary — useful when TCC lists multiple PaneKit entries.
    static var runningExecutablePath: String {
        Bundle.main.executableURL?.path
            ?? Bundle.main.bundleURL.path
            ?? ProcessInfo.processInfo.arguments.first
            ?? "(unknown)"
    }

    /// Bundle path shown in System Settings (prefer `.app` over the Mach-O inside).
    static var runningAppPath: String {
        Bundle.main.bundleURL.path
    }

    /// True when this process is not the recommended ~/Applications install.
    static var isNonRecommendedPath: Bool {
        let running = (runningAppPath as NSString).standardizingPath
        let recommended = (recommendedAppPath as NSString).standardizingPath
        return running != recommended
    }

    /// Identity string for this binary (CDHash when available) so guidance resets only when the build changes.
    static var currentBinaryIdentity: String {
        if let hash = codeDirectoryHash() {
            return "cdhash:\(hash)"
        }
        let path = runningAppPath
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "path:\(path)|mtime:\(mtime)"
    }

    /// Whether this process is trusted for Accessibility APIs (no dialog).
    static var isTrusted: Bool {
        let trusted = AXIsProcessTrusted()
        writeTrustStatusFile(trusted: trusted)
        return trusted
    }

    /// Quiet trust check (never prompts).
    static func check() -> Bool {
        isTrusted
    }

    /// Writes `/tmp/panekit-ax-status.txt` for diagnostics (path + trust).
    private static func writeTrustStatusFile(trusted: Bool) {
        let text = """
        trusted=\(trusted)
        path=\(runningAppPath)
        executable=\(runningExecutablePath)
        identity=\(currentBinaryIdentity)
        time=\(Date())
        """
        try? text.write(
            to: URL(fileURLWithPath: "/tmp/panekit-ax-status.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// On launch: if untrusted, open System Settings at most once per binary identity.
    /// Never calls Apple's modal prompt API.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        guard !didGuideThisSession else {
            return false
        }
        didGuideThisSession = true

        let identity = currentBinaryIdentity
        if defaults.string(forKey: openedSettingsIdentityKey) == identity {
            return false
        }

        defaults.set(identity, forKey: openedSettingsIdentityKey)
        openSystemSettings()
        return false
    }

    /// Menu / Layouts: open Accessibility settings only — never Apple's modal.
    @discardableResult
    static func requestExplicitly() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        didGuideThisSession = true
        defaults.set(currentBinaryIdentity, forKey: openedSettingsIdentityKey)
        openSystemSettings()
        return false
    }

    /// Opens System Settings → Privacy & Security → Accessibility
    /// (TR search: “Yardımcı uygulamaların bilgisayarı denetlemesine izin ver”;
    /// on macOS 27.2 the pane title may read “Aygıt Denetimi ve Veri Erişimi”).
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
        // Fallback when deep links fail (sandbox / older builds).
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if FileManager.default.fileExists(atPath: settingsApp.path) {
            NSWorkspace.shared.open(settingsApp)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
    }

    // MARK: - Codesign identity

    private static func codeDirectoryHash() -> String? {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", path]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("CDHash=") {
                return String(line.dropFirst("CDHash=".count))
            }
        }
        return nil
    }
}
