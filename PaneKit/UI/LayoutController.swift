import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Orchestrates Windows-style Snap Layouts: template picker → zone fill session.
final class LayoutController: NSObject {
    private let windowManager: WindowManager

    private var pickerPanel: NSPanel?
    private var sessionPanel: NSPanel?
    private var localMonitor: Any?
    private var session: LayoutSession?
    private var capturedFocused: ManagedWindow?
    private var targetScreen: NSScreen = NSScreen.main ?? NSScreen.screens[0]

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        super.init()
    }

    deinit {
        dismissAll()
    }

    // MARK: - Public

    /// True while the template picker or zone-fill session panel is on screen.
    var isShowingLayouts: Bool {
        pickerPanel != nil || sessionPanel != nil
    }

    /// Opens the layout template overlay (menu / hotkey / Option+green-button entry point).
    func showLayouts() {
        // Capture focus BEFORE our panel activates (needs AX; may be nil).
        // Never spam the TCC dialog from Layouts — AppDelegate prompts once at launch;
        // menu "İzin iste" can re-prompt explicitly.
        if AccessibilityPermission.isTrusted {
            capturedFocused = windowManager.focusedManagedWindow()
        } else {
            capturedFocused = nil
        }
        targetScreen = screenForPresentation(focused: capturedFocused)

        dismissAll()
        presentPicker()
    }

    func dismissAll() {
        removeKeyMonitor()
        pickerPanel?.orderOut(nil)
        pickerPanel = nil
        sessionPanel?.orderOut(nil)
        sessionPanel = nil
        session = nil
    }

    // MARK: - Picker

    private func presentPicker() {
        let content = buildPickerContent()
        let panel = makeFloatingPanel(contentSize: content.fittingSize)
        panel.contentView = content
        position(panel, size: content.fittingSize, on: targetScreen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pickerPanel = panel
        installKeyMonitor()
    }

    private func buildPickerContent() -> NSView {
        let root = NSView(frame: .zero)
        root.appearance = NSAppearance(named: .aqua)
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        // Opaque gray panel — translucent white washed out options over bright pages.
        root.layer?.backgroundColor = LayoutChrome.panelBackground.cgColor

        let title = NSTextField(labelWithString: "Layouts")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = LayoutChrome.titleColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "Şablon seç → bölgelere pencere yerleştir  ·  Esc")
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = LayoutChrome.subtitleColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        grid.xPlacement = .fill
        grid.yPlacement = .fill

        let templates = LayoutTemplate.all
        let columns = 4
        var rowViews: [NSView] = []
        for (index, template) in templates.enumerated() {
            let cell = LayoutTemplateCellView(template: template)
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.onSelect = { [weak self] selected in
                self?.beginSession(with: selected)
            }
            NSLayoutConstraint.activate([
                cell.widthAnchor.constraint(equalToConstant: 88),
                cell.heightAnchor.constraint(equalToConstant: 64),
            ])
            rowViews.append(cell)
            if rowViews.count == columns || index == templates.count - 1 {
                while rowViews.count < columns {
                    let spacer = NSView()
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    spacer.widthAnchor.constraint(equalToConstant: 88).isActive = true
                    spacer.heightAnchor.constraint(equalToConstant: 64).isActive = true
                    rowViews.append(spacer)
                }
                grid.addRow(with: rowViews)
                rowViews = []
            }
        }

        root.addSubview(title)
        root.addSubview(subtitle)
        root.addSubview(grid)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            grid.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])

        // Force layout to get fittingSize.
        root.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat = 14 + 88 * 4 + 6 * 3 + 14
        let height: CGFloat = 14 + 18 + 2 + 14 + 12 + 64 * 2 + 6 + 14
        root.widthAnchor.constraint(equalToConstant: width).isActive = true
        root.heightAnchor.constraint(equalToConstant: height).isActive = true
        return root
    }

    // MARK: - Session

    private func beginSession(with template: LayoutTemplate) {
        pickerPanel?.orderOut(nil)
        pickerPanel = nil

        let session = LayoutSession(
            template: template,
            screen: targetScreen,
            focusedWindow: capturedFocused
        )
        self.session = session
        presentSessionPanel(session)
    }

    private func presentSessionPanel(_ session: LayoutSession) {
        let content = buildSessionContent(session)
        // Taller panel so the candidate list under the board is never clipped.
        let size = NSSize(width: 440, height: 520)
        let panel = makeFloatingPanel(contentSize: size, movableBackground: false)
        panel.contentView = content
        position(panel, size: size, on: targetScreen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionPanel = panel
        installKeyMonitor()
        refreshSessionUI()
    }

    private func buildSessionContent(_ session: LayoutSession) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 520))
        root.appearance = NSAppearance(named: .aqua)
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = LayoutChrome.panelBackground.cgColor
        root.identifier = NSUserInterfaceItemIdentifier("layoutSessionRoot")

        let title = NSTextField(labelWithString: session.template.title)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = LayoutChrome.titleColor
        title.translatesAutoresizingMaskIntoConstraints = false
        title.identifier = NSUserInterfaceItemIdentifier("layoutSessionTitle")

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = LayoutChrome.subtitleColor
        status.translatesAutoresizingMaskIntoConstraints = false
        status.identifier = NSUserInterfaceItemIdentifier("layoutSessionStatus")
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let board = LayoutZoneBoardView()
        board.session = session
        board.translatesAutoresizingMaskIntoConstraints = false
        board.identifier = NSUserInterfaceItemIdentifier("layoutZoneBoard")
        board.onZoneClicked = { [weak self] zoneID in
            self?.handleZoneClick(zoneID)
        }
        board.onZoneResize = { [weak self] zoneID, delta in
            self?.handleZoneResize(zoneID, delta: delta)
        }
        board.onZoneDrop = { [weak self] zoneID, window in
            self?.place(window, in: zoneID, session: session)
        }

        let candidates = LayoutCandidatesListView()
        candidates.identifier = NSUserInterfaceItemIdentifier("layoutCandidatesList")
        candidates.onPick = { [weak self] window in
            self?.handleCandidatePick(window)
        }
        candidates.onOpenAccessibility = { [weak self] in
            self?.openAccessibilityFromLayouts(nil)
        }

        let done = NSButton(title: "Bitir / Done", target: self, action: #selector(finishSession(_:)))
        done.bezelStyle = .rounded
        done.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title)
        root.addSubview(status)
        root.addSubview(board)
        root.addSubview(candidates)
        root.addSubview(done)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -8),

            done.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            status.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            board.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            board.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            board.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            board.heightAnchor.constraint(equalToConstant: 210),

            candidates.topAnchor.constraint(equalTo: board.bottomAnchor, constant: 10),
            candidates.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            candidates.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            candidates.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            candidates.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])

        return root
    }

    private func refreshSessionUI() {
        guard let session,
              let root = sessionPanel?.contentView else { return }

        if let board = findView(LayoutZoneBoardView.self, in: root, id: "layoutZoneBoard") {
            board.session = session
            board.needsDisplay = true
        }

        if let status = findView(NSTextField.self, in: root, id: "layoutSessionStatus") {
            status.stringValue = statusText(for: session)
        }

        if let list = findView(LayoutCandidatesListView.self, in: root, id: "layoutCandidatesList") {
            list.reload(
                candidates: availableCandidates(for: session),
                accessibilityTrusted: AccessibilityPermission.isTrusted
            )
        }

        // Keep the layout panel above apps raised by AX placement (e.g. System Settings).
        sessionPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func statusText(for session: LayoutSession) -> String {
        if session.isComplete {
            if session.pendingZoneID != nil {
                return "Yeniden ata: sürükle veya listeden seç · Bitir kapatır"
            }
            return "Tamam · sürükle/tıkla = yeniden ata · Bitir / Done"
        }
        if !session.hasPlacedFirst {
            let name = session.focusedWindow?.appName ?? "odak penceresi / focused"
            return "Bölgeye tıkla → \(name)  ·  veya listeden sürükle-bırak"
        }
        if session.pendingZoneID != nil {
            return "Listeden sürükle → bölgeye bırak  /  Drag onto a zone"
        }
        return "Listeden sürükle-bırak veya bölgeye tıkla + seç"
    }

    // MARK: - Interaction

    private func handleZoneClick(_ zoneID: String) {
        guard let session else { return }

        // Filled zone: select for reassignment (size still via −/+).
        if session.window(in: zoneID) != nil {
            session.selectPendingZone(zoneID)
            refreshSessionUI()
            return
        }

        if !session.hasPlacedFirst {
            // First placement: focused window into clicked zone.
            if let focused = session.focusedWindow {
                place(focused, in: zoneID, session: session)
            } else if let first = availableCandidates(for: session).first {
                place(first, in: zoneID, session: session)
            } else {
                // No focused window — mark pending and show whatever list we have.
                session.selectPendingZone(zoneID)
                refreshSessionUI()
            }
            return
        }

        // Subsequent: select zone as pending for candidate pick.
        session.selectPendingZone(zoneID)
        refreshSessionUI()
    }

    private func handleCandidatePick(_ window: ManagedWindow) {
        guard let session else { return }

        if !session.hasPlacedFirst {
            // Prefer explicit pending zone, else first empty.
            if let pending = session.pendingZoneID {
                place(window, in: pending, session: session)
            } else if let zone = session.emptyZones.first {
                place(window, in: zone.id, session: session)
            }
            return
        }

        if let pending = session.pendingZoneID {
            place(window, in: pending, session: session)
            return
        }

        // No pending zone — auto-fill next empty if user clicks a candidate.
        if let zone = session.emptyZones.first {
            place(window, in: zone.id, session: session)
        }
    }

    private func handleZoneResize(_ zoneID: String, delta: CGFloat) {
        guard let session,
              let window = session.window(in: zoneID),
              let zone = session.template.zones.first(where: { $0.id == zoneID }),
              session.adjustScale(for: zoneID, delta: delta) != nil else { return }
        let cocoa = session.absoluteRect(for: zone)
        windowManager.place(
            window,
            cocoaFrame: cocoa,
            on: session.screen,
            spill: spillDirection(for: zoneID, in: session.template)
        )
        refreshSessionUI()
    }

    private func place(_ window: ManagedWindow, in zoneID: String, session: LayoutSession) {
        guard session.template.zones.contains(where: { $0.id == zoneID }) else { return }
        // Auto-close only when filling the last empty zone — not when reassigning.
        let filledEmptyZone = session.window(in: zoneID) == nil
        session.assign(window, to: zoneID)

        // Re-apply EVERY assignment after each place. Otherwise a stubborn second
        // window (Brave / App Store) can stay wide and cover the first, or the
        // first can drift when the second is raised — looking like both sit in the middle.
        // Bring the just-selected window to front.
        reapplyAllAssignments(session, bringToFront: window)

        if session.isComplete && filledEmptyZone {
            // One quiet settle pass (avoid stacked re-applies that flicker gaps between tiles).
            // Prefer the first zone (usually left) so the primary app isn’t buried under Brave.
            let primary = primaryWindow(in: session) ?? window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.reapplyAllAssignments(session, bringToFront: primary)
                self?.refreshSessionUI()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.windowManager.bringToFront(primary)
                    self?.dismissAll()
                }
            }
        } else if session.isComplete {
            refreshSessionUI()
        } else {
            if let next = session.emptyZones.first {
                session.selectPendingZone(next.id)
            }
            refreshSessionUI()
        }
    }

    /// First template zone’s window, else the session’s original focused window if assigned.
    private func primaryWindow(in session: LayoutSession) -> ManagedWindow? {
        if let firstZone = session.template.zones.first,
           let window = session.window(in: firstZone.id) {
            return window
        }
        if let focused = session.focusedWindow, session.isAssigned(focused) {
            return focused
        }
        return nil
    }

    /// Places all assigned windows; optionally activates `bringToFront` last so it stays on top.
    private func reapplyAllAssignments(_ session: LayoutSession, bringToFront: ManagedWindow? = nil) {
        let ordered = session.template.zones.compactMap { zone -> (LayoutZone, ManagedWindow)? in
            guard let window = session.window(in: zone.id) else { return nil }
            return (zone, window)
        }
        for (zone, window) in ordered {
            let cocoa = session.absoluteRect(for: zone)
            // Don’t activate mid-pass — only the chosen window should end on top.
            windowManager.place(
                window,
                cocoaFrame: cocoa,
                on: session.screen,
                activate: false,
                spill: spillDirection(for: zone.id, in: session.template)
            )
        }
        if let front = bringToFront {
            windowManager.bringToFront(front)
        }
    }

    /// Outer columns/rows spill off-screen; center stays centered — keeps ⅓ tiles from covering neighbors.
    private func spillDirection(for zoneID: String, in template: LayoutTemplate) -> WindowManager.ZoneSpill {
        switch zoneID {
        case "left", "bottom", "bottomLeft", "leftBottom", "topLeft", "rightBottom":
            return .outwardLow
        case "right", "top", "topRight", "rightTop", "leftTop", "bottomRight":
            return .outwardHigh
        case "center":
            return .center
        default:
            // Heuristic from normalized rect.
            if let zone = template.zones.first(where: { $0.id == zoneID }) {
                if zone.rect.minX < 0.05 { return .outwardLow }
                if zone.rect.maxX > 0.95 { return .outwardHigh }
                if zone.rect.minY < 0.05 { return .outwardLow }
                if zone.rect.maxY > 0.95 { return .outwardHigh }
            }
            return .center
        }
    }

    private func availableCandidates(for session: LayoutSession) -> [ManagedWindow] {
        var list = windowManager.listCandidateWindows()
        // Ensure focused window is present even if listing missed it.
        if let focused = session.focusedWindow,
           !list.contains(where: { $0.id == focused.id }) {
            list.insert(focused, at: 0)
        }
        return list.filter { !session.isAssigned($0) }
    }

    @objc private func finishSession(_ sender: Any?) {
        dismissAll()
    }

    @objc private func openAccessibilityFromLayouts(_ sender: Any?) {
        AccessibilityPermission.requestExplicitly()
    }

    // MARK: - Panel helpers

    private func makeFloatingPanel(contentSize: NSSize, movableBackground: Bool = true) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Opaque so bright browser pages don't wash out the layout thumbnails.
        panel.isOpaque = true
        panel.backgroundColor = LayoutChrome.panelBackground
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        // Session panel must not steal clicks into drag-move; candidate rows need mouseDown.
        panel.isMovableByWindowBackground = movableBackground
        return panel
    }

    private func position(_ panel: NSPanel, size: NSSize, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y - size.height / 2
        )

        // Keep fully inside visible frame.
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)

        // If mouse is off this screen, center on screen.
        if !visible.contains(mouse) {
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func screenForPresentation(focused: ManagedWindow?) -> NSScreen {
        if let focused,
           let axFrame = windowAXFrame(focused),
           let cocoa = Optional(ScreenHelper.accessibilityToCocoa(axFrame)) {
            return ScreenHelper.screen(containing: cocoa)
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func windowAXFrame(_ window: ManagedWindow) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window.element, kAXSizeAttribute as CFString, &sizeRef) == .success,
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

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.dismissAll()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func findView<T: NSView>(_ type: T.Type, in root: NSView, id: String) -> T? {
        if root.identifier?.rawValue == id, let typed = root as? T {
            return typed
        }
        for sub in root.subviews {
            if let found = findView(type, in: sub, id: id) {
                return found
            }
        }
        return nil
    }
}
