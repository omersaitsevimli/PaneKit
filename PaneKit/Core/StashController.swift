import AppKit
import ApplicationServices

/// Rectangle-style stash: slide a window mostly off-screen; cursor on the peek strip reveals it.
final class StashController {
    enum Edge: String {
        case left, right, top, bottom
    }

    private struct Entry {
        let window: ManagedWindow
        var edge: Edge
        var restoredCocoa: CGRect
        var stashedCocoa: CGRect
        var screenKey: String
        var revealed: Bool
    }

    private let windowManager: WindowManager
    private var entries: [String: Entry] = [:]
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var reStashWork: [String: DispatchWorkItem] = [:]

    /// Visible strip while stashed (points).
    private let peek: CGFloat = 14
    /// Hit slop around the peek for reveal.
    private let hitSlop: CGFloat = 18

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    deinit {
        stop()
    }

    var stashedIDs: Set<String> {
        Set(entries.keys)
    }

    func isStashed(id: String) -> Bool {
        entries[id] != nil
    }

    func start() {
        stopMouseMonitors()
        guard UserPreferences.shared.stashEdgeRevealEnabled else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.handleMouseMove(NSEvent.mouseLocation)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove(NSEvent.mouseLocation)
            return event
        }
    }

    func stop() {
        stopMouseMonitors()
        reStashWork.values.forEach { $0.cancel() }
        reStashWork.removeAll()
    }

    func reload() {
        start()
    }

    private func stopMouseMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    // MARK: - Public actions

    /// Stash focused window, or fully unstash if it is already stashed.
    func toggleFocused() {
        guard AccessibilityPermission.isTrusted else { return }
        guard let focused = windowManager.focusedManagedWindow() else {
            NSSound.beep()
            return
        }
        if entries[focused.id] != nil {
            unstash(id: focused.id, animateToRestored: true)
        } else {
            stash(focused)
        }
    }

    func unstashAll() {
        let ids = Array(entries.keys)
        for id in ids {
            unstash(id: id, animateToRestored: true)
        }
    }

    // MARK: - Stash / unstash

    private func stash(_ window: ManagedWindow) {
        guard let ax = windowManager.frameAX(of: window.element) else {
            NSSound.beep()
            return
        }
        let cocoa = ScreenHelper.accessibilityToCocoa(ax)
        let screen = ScreenHelper.screen(containing: cocoa)
        let edge = nearestEdge(for: cocoa, on: screen)
        let stashed = stashedFrame(for: cocoa, edge: edge, on: screen)

        windowManager.setCocoaFrame(window.element, cocoaFrame: stashed, on: screen)
        entries[window.id] = Entry(
            window: window,
            edge: edge,
            restoredCocoa: cocoa,
            stashedCocoa: stashed,
            screenKey: ScreenHelper.screenKey(screen),
            revealed: false
        )
        start()
    }

    private func unstash(id: String, animateToRestored: Bool) {
        guard var entry = entries.removeValue(forKey: id) else { return }
        reStashWork[id]?.cancel()
        reStashWork[id] = nil

        if animateToRestored {
            let screen = screenMatching(entry.screenKey) ?? ScreenHelper.screen(containing: entry.restoredCocoa)
            windowManager.setCocoaFrame(entry.window.element, cocoaFrame: entry.restoredCocoa, on: screen)
        }
        _ = entry
        if entries.isEmpty {
            stopMouseMonitors()
        }
    }

    private func reveal(_ id: String) {
        guard var entry = entries[id], !entry.revealed else { return }
        reStashWork[id]?.cancel()
        reStashWork[id] = nil
        let screen = screenMatching(entry.screenKey) ?? ScreenHelper.screen(containing: entry.restoredCocoa)
        windowManager.setCocoaFrame(entry.window.element, cocoaFrame: entry.restoredCocoa, on: screen)
        entry.revealed = true
        entries[id] = entry
    }

    private func hideAgain(_ id: String) {
        guard var entry = entries[id], entry.revealed else { return }
        let screen = screenMatching(entry.screenKey) ?? ScreenHelper.screen(containing: entry.stashedCocoa)
        // Refresh stashed frame in case screen layout changed.
        entry.stashedCocoa = stashedFrame(for: entry.restoredCocoa, edge: entry.edge, on: screen)
        windowManager.setCocoaFrame(entry.window.element, cocoaFrame: entry.stashedCocoa, on: screen)
        entry.revealed = false
        entries[id] = entry
    }

    // MARK: - Mouse

    private func handleMouseMove(_ cocoaPoint: CGPoint) {
        guard UserPreferences.shared.stashEdgeRevealEnabled else { return }
        guard !entries.isEmpty else { return }

        for (id, entry) in entries {
            let hit = peekHitRect(for: entry).insetBy(dx: -hitSlop, dy: -hitSlop)
            let overWindow = entry.revealed && entry.restoredCocoa.insetBy(dx: -8, dy: -8).contains(cocoaPoint)
            let overPeek = hit.contains(cocoaPoint)

            if overPeek || overWindow {
                reStashWork[id]?.cancel()
                reStashWork[id] = nil
                if !entry.revealed {
                    reveal(id)
                }
            } else if entry.revealed {
                scheduleReStash(id: id)
            }
        }
    }

    private func scheduleReStash(id: String) {
        guard reStashWork[id] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.reStashWork[id] = nil
            self?.hideAgain(id)
        }
        reStashWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func peekHitRect(for entry: Entry) -> CGRect {
        let s = entry.stashedCocoa
        switch entry.edge {
        case .left:
            return CGRect(x: s.maxX - peek, y: s.minY, width: peek, height: s.height)
        case .right:
            return CGRect(x: s.minX, y: s.minY, width: peek, height: s.height)
        case .top:
            return CGRect(x: s.minX, y: s.minY, width: s.width, height: peek)
        case .bottom:
            return CGRect(x: s.minX, y: s.maxY - peek, width: s.width, height: peek)
        }
    }

    // MARK: - Geometry

    private func nearestEdge(for cocoa: CGRect, on screen: NSScreen) -> Edge {
        let visible = screen.visibleFrame
        let distLeft = cocoa.midX - visible.minX
        let distRight = visible.maxX - cocoa.midX
        let distBottom = cocoa.midY - visible.minY
        let distTop = visible.maxY - cocoa.midY
        let minDist = min(distLeft, distRight, distBottom, distTop)
        if minDist == distLeft { return .left }
        if minDist == distRight { return .right }
        if minDist == distTop { return .top }
        return .bottom
    }

    private func stashedFrame(for restored: CGRect, edge: Edge, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        // Keep size; slide so only `peek` remains inside the visible frame.
        switch edge {
        case .left:
            return CGRect(
                x: visible.minX - restored.width + peek,
                y: restored.minY,
                width: restored.width,
                height: restored.height
            )
        case .right:
            return CGRect(
                x: visible.maxX - peek,
                y: restored.minY,
                width: restored.width,
                height: restored.height
            )
        case .top:
            return CGRect(
                x: restored.minX,
                y: visible.maxY - peek,
                width: restored.width,
                height: restored.height
            )
        case .bottom:
            return CGRect(
                x: restored.minX,
                y: visible.minY - restored.height + peek,
                width: restored.width,
                height: restored.height
            )
        }
    }

    private func screenMatching(_ key: String) -> NSScreen? {
        ScreenHelper.sortedScreens.first { ScreenHelper.screenKey($0) == key }
    }
}
