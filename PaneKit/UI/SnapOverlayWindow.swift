import AppKit

/// Semi-transparent preview of the snap target while dragging a window to an edge.
final class SnapOverlayWindow: NSWindow {
    static let shared = SnapOverlayWindow()

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = OverlayView()
    }

    func show(at cocoaFrame: CGRect) {
        setFrame(cocoaFrame, display: true)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}

private final class OverlayView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8)
        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
