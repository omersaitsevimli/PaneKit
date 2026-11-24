import AppKit
import ApplicationServices

/// Saves / restores multi-window workspaces and optionally reapplies on display connect.
final class WorkspaceController {
    private let windowManager: WindowManager
    private var screenObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastScreenCount: Int = NSScreen.screens.count

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        lastScreenCount = NSScreen.screens.count
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenParametersChanged()
        }
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - Persistence helpers

    var workspaces: [Workspace] {
        UserPreferences.shared.workspaces
    }

    // MARK: - Save / restore / delete

    @discardableResult
    func saveCurrentWorkspace(named name: String) -> Workspace? {
        guard AccessibilityPermission.isTrusted else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let screens = ScreenHelper.sortedScreens
        guard !screens.isEmpty else { return nil }

        var entries: [WorkspaceEntry] = []
        for window in windowManager.listCandidateWindows() {
            guard let bundleID = window.appBundleID, !bundleID.isEmpty else { continue }
            if windowManager.isWindowStashed?(window.id) == true { continue }
            if UserPreferences.shared.pinModeEnabled,
               bundleID == UserPreferences.shared.pinAppBundleID {
                continue
            }
            guard let ax = windowManager.frameAX(of: window.element) else { continue }
            let cocoa = ScreenHelper.accessibilityToCocoa(ax)
            let screen = ScreenHelper.screen(containing: cocoa)
            guard let screenIndex = screens.firstIndex(where: { ScreenHelper.screenKey($0) == ScreenHelper.screenKey(screen) }) else { continue }
            let area = ScreenHelper.workArea(for: screen)
            guard area.width > 1, area.height > 1 else { continue }

            let nx = (cocoa.minX - area.minX) / area.width
            let ny = (cocoa.minY - area.minY) / area.height
            let nw = cocoa.width / area.width
            let nh = cocoa.height / area.height

            entries.append(
                WorkspaceEntry(
                    bundleID: bundleID,
                    titleHint: window.title,
                    screenIndex: screenIndex,
                    nx: nx,
                    ny: ny,
                    nw: max(nw, 0.05),
                    nh: max(nh, 0.05)
                )
            )
        }

        guard !entries.isEmpty else { return nil }

        var list = UserPreferences.shared.workspaces
        let workspace = Workspace(name: trimmed, entries: entries)
        list.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(workspace, at: 0)
        // Cap stored workspaces.
        if list.count > 20 {
            list = Array(list.prefix(20))
        }
        UserPreferences.shared.workspaces = list
        UserPreferences.shared.lastWorkspaceID = workspace.id
        return workspace
    }

    @discardableResult
    func restore(_ workspace: Workspace) -> Int {
        guard AccessibilityPermission.isTrusted else { return 0 }
        let screens = ScreenHelper.sortedScreens
        guard !screens.isEmpty else { return 0 }

        var available = windowManager.listCandidateWindows()
        var placed = 0

        for entry in workspace.entries {
            let screenIndex = min(max(entry.screenIndex, 0), screens.count - 1)
            let screen = screens[screenIndex]
            let area = ScreenHelper.workArea(for: screen)
            let target = CGRect(
                x: area.minX + entry.nx * area.width,
                y: area.minY + entry.ny * area.height,
                width: entry.nw * area.width,
                height: entry.nh * area.height
            )

            guard let matchIndex = Self.bestMatchIndex(
                for: entry,
                in: available
            ) else { continue }

            let match = available.remove(at: matchIndex)
            windowManager.place(
                match,
                cocoaFrame: target,
                on: screen,
                activate: placed == 0,
                clampToZone: false,
                spill: .center
            )
            placed += 1
        }

        if placed > 0 {
            UserPreferences.shared.lastWorkspaceID = workspace.id
        }
        return placed
    }

    func restoreWorkspace(id: String) -> Int {
        guard let workspace = UserPreferences.shared.workspaces.first(where: { $0.id == id }) else {
            return 0
        }
        return restore(workspace)
    }

    func restoreLastWorkspace() -> Int {
        if let id = UserPreferences.shared.lastWorkspaceID {
            let count = restoreWorkspace(id: id)
            if count > 0 { return count }
        }
        guard let first = UserPreferences.shared.workspaces.first else { return 0 }
        return restore(first)
    }

    func deleteWorkspace(id: String) {
        var list = UserPreferences.shared.workspaces
        list.removeAll { $0.id == id }
        UserPreferences.shared.workspaces = list
        if UserPreferences.shared.lastWorkspaceID == id {
            UserPreferences.shared.lastWorkspaceID = list.first?.id
        }
        if UserPreferences.shared.displayConnectWorkspaceID == id {
            UserPreferences.shared.displayConnectWorkspaceID = nil
        }
    }

    func setDisplayConnectWorkspace(id: String?) {
        UserPreferences.shared.displayConnectWorkspaceID = id
        // Keep flag on the chosen workspace for clarity in the model.
        var list = UserPreferences.shared.workspaces
        for i in list.indices {
            list[i].restoreOnDisplayConnect = (list[i].id == id)
        }
        UserPreferences.shared.workspaces = list
    }

    // MARK: - Display connect

    private func handleScreenParametersChanged() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluateDisplayConnectRestore()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func evaluateDisplayConnectRestore() {
        let count = NSScreen.screens.count
        let increased = count > lastScreenCount
        lastScreenCount = count
        guard increased else { return }
        guard UserPreferences.shared.restoreWorkspaceOnDisplayConnect else { return }
        guard let id = UserPreferences.shared.displayConnectWorkspaceID else { return }
        // Give newly attached displays / apps a moment to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            _ = self?.restoreWorkspace(id: id)
        }
    }

    // MARK: - Matching

    private static func bestMatchIndex(for entry: WorkspaceEntry, in windows: [ManagedWindow]) -> Int? {
        let sameApp = windows.enumerated().filter { $0.element.appBundleID == entry.bundleID }
        guard !sameApp.isEmpty else { return nil }

        let hint = entry.titleHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            if let exact = sameApp.first(where: { $0.element.title == hint }) {
                return exact.offset
            }
            if let partial = sameApp.first(where: {
                !$0.element.title.isEmpty && (
                    $0.element.title.localizedCaseInsensitiveContains(hint)
                        || hint.localizedCaseInsensitiveContains($0.element.title)
                )
            }) {
                return partial.offset
            }
        }
        return sameApp.first?.offset
    }
}
