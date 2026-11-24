import AppKit

extension NSPasteboard.PasteboardType {
    static let paneKitWindowID = NSPasteboard.PasteboardType("com.panekit.layout.windowID")
}

/// Shared Layouts chrome — opaque gray so options stay readable over bright pages.
enum LayoutChrome {
    static var panelBackground: NSColor {
        NSColor(calibratedWhite: 0.82, alpha: 1.0)
    }

    static var cellBackground: NSColor {
        NSColor(calibratedWhite: 0.92, alpha: 1.0)
    }

    static var cellHoverBackground: NSColor {
        NSColor(calibratedWhite: 0.96, alpha: 1.0)
    }

    static var zoneFill: NSColor {
        NSColor(calibratedWhite: 0.45, alpha: 1.0)
    }

    static var zoneFillHover: NSColor {
        NSColor(calibratedWhite: 0.32, alpha: 1.0)
    }

    static var zoneStroke: NSColor {
        NSColor(calibratedWhite: 0.22, alpha: 1.0)
    }

    static var titleColor: NSColor {
        NSColor(calibratedWhite: 0.12, alpha: 1.0)
    }

    static var subtitleColor: NSColor {
        NSColor(calibratedWhite: 0.28, alpha: 1.0)
    }
}

/// Carries the dragged `ManagedWindow` for in-app Layouts drag-and-drop.
enum LayoutDragPayload {
    static var window: ManagedWindow?
}

// MARK: - Template thumbnail

/// Draws a miniature layout template with rounded zones (Windows Snap style).
final class LayoutTemplateThumbnailView: NSView {
    var template: LayoutTemplate = .verticalHalves {
        didSet { needsDisplay = true }
    }
    var highlightedZoneIDs: Set<String> = [] {
        didSet { needsDisplay = true }
    }
    var assignedIcons: [String: NSImage] = [:] {
        didSet { needsDisplay = true }
    }
    var isHovering = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gap: CGFloat = 3
        let radius: CGFloat = 3
        let boundsInset = bounds.insetBy(dx: 4, dy: 4)

        let emptyFill = isHovering ? LayoutChrome.zoneFillHover : LayoutChrome.zoneFill
        let filledFill = NSColor.controlAccentColor.withAlphaComponent(0.75)
        let highlightFill = NSColor.controlAccentColor
        let stroke = LayoutChrome.zoneStroke

        for zone in template.zones {
            let r = zoneRect(zone, in: boundsInset, gap: gap)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)

            if highlightedZoneIDs.contains(zone.id) {
                highlightFill.setFill()
            } else if assignedIcons[zone.id] != nil {
                filledFill.setFill()
            } else {
                emptyFill.setFill()
            }
            path.fill()
            stroke.setStroke()
            path.lineWidth = 1.25
            path.stroke()

            if let icon = assignedIcons[zone.id] {
                let iconSize = min(18, min(r.width, r.height) - 6)
                guard iconSize > 8 else { continue }
                let iconRect = NSRect(
                    x: r.midX - iconSize / 2,
                    y: r.midY - iconSize / 2,
                    width: iconSize,
                    height: iconSize
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
    }

    private func zoneRect(_ zone: LayoutZone, in container: NSRect, gap: CGFloat) -> NSRect {
        // Normalized Cocoa space (origin bottom-left) maps directly into our non-flipped view.
        var r = NSRect(
            x: container.origin.x + zone.rect.origin.x * container.width,
            y: container.origin.y + zone.rect.origin.y * container.height,
            width: zone.rect.width * container.width,
            height: zone.rect.height * container.height
        )
        r = r.insetBy(dx: gap / 2, dy: gap / 2)
        return r
    }
}

// MARK: - Clickable template cell

final class LayoutTemplateCellView: NSView {
    let template: LayoutTemplate
    var onSelect: ((LayoutTemplate) -> Void)?

    private let thumbnail = LayoutTemplateThumbnailView()
    private var tracking: NSTrackingArea?

    init(template: LayoutTemplate) {
        self.template = template
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = LayoutChrome.cellBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.65, alpha: 1).cgColor

        thumbnail.template = template
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            thumbnail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            thumbnail.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            thumbnail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        thumbnail.isHovering = true
        layer?.backgroundColor = LayoutChrome.cellHoverBackground.cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        thumbnail.isHovering = false
        layer?.backgroundColor = LayoutChrome.cellBackground.cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.65, alpha: 1).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(template)
    }
}

// MARK: - Interactive session zone board

final class LayoutZoneBoardView: NSView {
    var session: LayoutSession? {
        didSet { needsDisplay = true; rebuildHitZones() }
    }
    var onZoneClicked: ((String) -> Void)?
    var onZoneResize: ((String, CGFloat) -> Void)?
    /// Drag-and-drop from the candidate list onto a zone.
    var onZoneDrop: ((String, ManagedWindow) -> Void)?

    private var hitZones: [(id: String, rect: NSRect)] = []
    private var resizeButtons: [(zoneID: String, minus: NSRect, plus: NSRect)] = []
    private var dropHoverZoneID: String? {
        didSet { if oldValue != dropHoverZoneID { needsDisplay = true } }
    }

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.paneKitWindowID])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let session else { return }

        let gap: CGFloat = 6
        let radius: CGFloat = 8
        let container = bounds.insetBy(dx: 8, dy: 8)

        let emptyFill = LayoutChrome.zoneFill.withAlphaComponent(0.35)
        let pendingFill = NSColor.controlAccentColor.withAlphaComponent(0.55)
        let filledFill = NSColor.controlAccentColor.withAlphaComponent(0.40)
        let dropFill = NSColor.systemGreen.withAlphaComponent(0.50)
        let stroke = LayoutChrome.zoneStroke

        resizeButtons.removeAll()

        for zone in session.template.zones {
            let r = zoneRect(zone, in: container, gap: gap)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)

            if dropHoverZoneID == zone.id {
                dropFill.setFill()
            } else if session.pendingZoneID == zone.id {
                pendingFill.setFill()
            } else if session.window(in: zone.id) != nil {
                filledFill.setFill()
            } else {
                emptyFill.setFill()
            }
            path.fill()
            stroke.setStroke()
            path.lineWidth = dropHoverZoneID == zone.id ? 2.5 : 1.5
            path.stroke()

            if let window = session.window(in: zone.id) {
                drawAssignment(window, in: r)
                let buttons = drawResizeControls(in: r)
                resizeButtons.append((zone.id, buttons.minus, buttons.plus))
                if session.pendingZoneID == zone.id {
                    drawHint("Yeniden ata / Reassign", in: r)
                }
            } else if dropHoverZoneID == zone.id {
                drawHint("Bırak / Drop", in: r)
            } else if session.pendingZoneID == zone.id {
                drawHint("Pencere seç / Pick window", in: r)
            } else if !session.hasPlacedFirst {
                drawHint("Tıkla veya bırak / Click or drop", in: r)
            } else {
                drawHint("+", in: r)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        for entry in resizeButtons {
            if entry.minus.contains(point) {
                onZoneResize?(entry.zoneID, -0.1)
                return
            }
            if entry.plus.contains(point) {
                onZoneResize?(entry.zoneID, 0.1)
                return
            }
        }

        if let hit = hitZones.first(where: { $0.rect.contains(point) }) {
            onZoneClicked?(hit.id)
        }
    }

    // MARK: - Drop target

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropHover(with: sender)
        return dropHoverZoneID == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropHover(with: sender)
        return dropHoverZoneID == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHoverZoneID = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateDropHover(with: sender)
        return dropHoverZoneID != nil && LayoutDragPayload.window != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropHoverZoneID = nil
            LayoutDragPayload.window = nil
        }
        guard let zoneID = dropHoverZoneID,
              let window = LayoutDragPayload.window ?? windowFromPasteboard(sender.draggingPasteboard)
        else { return false }
        onZoneDrop?(zoneID, window)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropHoverZoneID = nil
    }

    private func updateDropHover(with sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        dropHoverZoneID = hitZones.first(where: { $0.rect.contains(point) })?.id
    }

    private func windowFromPasteboard(_ pasteboard: NSPasteboard) -> ManagedWindow? {
        guard let id = pasteboard.string(forType: .paneKitWindowID),
              let window = LayoutDragPayload.window,
              window.id == id else {
            return LayoutDragPayload.window
        }
        return window
    }

    private func rebuildHitZones() {
        hitZones.removeAll()
        guard let session else { return }
        let gap: CGFloat = 6
        let container = bounds.insetBy(dx: 8, dy: 8)
        for zone in session.template.zones {
            hitZones.append((zone.id, zoneRect(zone, in: container, gap: gap)))
        }
    }

    override func layout() {
        super.layout()
        rebuildHitZones()
    }

    private func zoneRect(_ zone: LayoutZone, in container: NSRect, gap: CGFloat) -> NSRect {
        var r = NSRect(
            x: container.origin.x + zone.rect.origin.x * container.width,
            y: container.origin.y + zone.rect.origin.y * container.height,
            width: zone.rect.width * container.width,
            height: zone.rect.height * container.height
        )
        r = r.insetBy(dx: gap / 2, dy: gap / 2)
        return r
    }

    private func drawAssignment(_ window: ManagedWindow, in rect: NSRect) {
        let iconSize: CGFloat = min(36, min(rect.width, rect.height) * 0.35)
        if let icon = window.appIcon {
            let iconRect = NSRect(
                x: rect.midX - iconSize / 2,
                y: rect.midY - iconSize / 2 + 6,
                width: iconSize,
                height: iconSize
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        let title = window.appName as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: LayoutChrome.titleColor,
        ]
        let size = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - iconSize / 2 - 4 - size.height
        )
        if titlePoint.y > rect.minY + 4 {
            title.draw(at: titlePoint, withAttributes: attrs)
        }
    }

    private func drawResizeControls(in rect: NSRect) -> (minus: NSRect, plus: NSRect) {
        let buttonSize: CGFloat = 22
        let padding: CGFloat = 8
        let minus = NSRect(
            x: rect.minX + padding,
            y: rect.minY + padding,
            width: buttonSize,
            height: buttonSize
        )
        let plus = NSRect(
            x: rect.minX + padding + buttonSize + 6,
            y: rect.minY + padding,
            width: buttonSize,
            height: buttonSize
        )
        drawRoundButton("−", in: minus)
        drawRoundButton("+", in: plus)
        return (minus, plus)
    }

    private func drawRoundButton(_ title: String, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let ns = title as NSString
        let size = ns.size(withAttributes: attrs)
        ns.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawHint(_ text: String, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: text == "+" ? 22 : 11, weight: .medium),
            .foregroundColor: LayoutChrome.subtitleColor,
        ]
        let ns = text as NSString
        let size = ns.size(withAttributes: attrs)
        ns.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - Candidates list

/// Plain stack (no NSScrollView documentView) — AppKit scroll+AutoLayout was hiding all rows.
final class LayoutCandidatesListView: NSView {
    var onPick: ((ManagedWindow) -> Void)?
    var onOpenAccessibility: (() -> Void)?

    private let stack = NSStackView()
    private var rowWidthConstraints: [ObjectIdentifier: NSLayoutConstraint] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        appearance = NSAppearance(named: .aqua)
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.65, alpha: 1).cgColor
        layer?.backgroundColor = LayoutChrome.cellBackground.cgColor

        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.identifier = NSUserInterfaceItemIdentifier("layoutCandidatesStack")
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(candidates: [ManagedWindow], accessibilityTrusted: Bool) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowWidthConstraints.removeAll()

        if candidates.isEmpty {
            if !accessibilityTrusted {
                let button = NSButton(
                    title: "Accessibility izni yok — tıkla → Ayarlar",
                    target: self,
                    action: #selector(openAccessibility)
                )
                button.bezelStyle = .inline
                button.isBordered = false
                button.font = NSFont.systemFont(ofSize: 11)
                button.contentTintColor = LayoutChrome.subtitleColor
                button.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(button)
            } else {
                let empty = NSTextField(labelWithString: "Başka uygun pencere yok — TextEdit / Notes açın")
                empty.font = NSFont.systemFont(ofSize: 11)
                empty.textColor = LayoutChrome.subtitleColor
                empty.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(empty)
            }
        } else {
            let header = NSTextField(labelWithString: "Sürükle → bölgeye bırak  ·  veya tıkla / Drag onto a zone · or click")
            header.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            header.textColor = LayoutChrome.subtitleColor
            header.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(header)

            // Cap visible rows so the panel stays usable; prefer frontmost first (already sorted).
            for candidate in candidates.prefix(8) {
                let row = LayoutCandidateRowView(managedWindow: candidate)
                row.translatesAutoresizingMaskIntoConstraints = false
                row.onPick = { [weak self] window in
                    self?.onPick?(window)
                }
                stack.addArrangedSubview(row)
                let width = row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16)
                width.isActive = true
                rowWidthConstraints[ObjectIdentifier(row)] = width
            }
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc private func openAccessibility() {
        onOpenAccessibility?()
    }
}

// MARK: - Candidate row

final class LayoutCandidateRowView: NSView, NSDraggingSource {
    let managedWindow: ManagedWindow
    var onPick: ((ManagedWindow) -> Void)?

    private var tracking: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    init(managedWindow: ManagedWindow) {
        self.managedWindow = managedWindow
        super.init(frame: .zero)
        // Lock light chrome so Dark Mode doesn’t turn labels white on our gray panel.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 1).cgColor

        let iconView = NSImageView()
        iconView.image = managedWindow.appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: managedWindow.displayTitle)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = LayoutChrome.titleColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        // Prevent vibrancy / dark-mode override of textColor.
        label.drawsBackground = false
        label.isBezeled = false

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 1).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent, !didStartDrag else { return }
        let start = mouseDownEvent.locationInWindow
        let now = event.locationInWindow
        let distance = hypot(now.x - start.x, now.y - start.y)
        guard distance >= 4 else { return }
        didStartDrag = true
        beginWindowDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        // Click (no drag) still assigns via pending zone / auto-fill.
        if mouseDownEvent != nil, !didStartDrag {
            onPick?(managedWindow)
        }
        mouseDownEvent = nil
        didStartDrag = false
    }

    private func beginWindowDrag(with event: NSEvent) {
        LayoutDragPayload.window = managedWindow

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(managedWindow.id, forType: .paneKitWindowID)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragRect = bounds.insetBy(dx: 2, dy: 2)
        let image = dragPreviewImage()
        draggingItem.setDraggingFrame(dragRect, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func dragPreviewImage() -> NSImage {
        let size = NSSize(width: max(120, bounds.width), height: 34)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        if let icon = managedWindow.appIcon {
            icon.draw(in: NSRect(x: 8, y: 8, width: 18, height: 18))
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        (managedWindow.appName as NSString).draw(
            at: NSPoint(x: 34, y: 9),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if operation == [] {
            LayoutDragPayload.window = nil
        }
        mouseDownEvent = nil
        didStartDrag = false
    }
}
