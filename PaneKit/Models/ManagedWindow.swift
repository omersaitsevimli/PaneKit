import AppKit
import ApplicationServices
import Foundation

/// A resizable on-screen window discovered via Accessibility.
struct ManagedWindow: Identifiable, Hashable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let title: String
    let appName: String
    let appBundleID: String?
    let appIcon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ManagedWindow, rhs: ManagedWindow) -> Bool {
        lhs.id == rhs.id
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return appName
        }
        return "\(appName) — \(trimmed)"
    }
}
