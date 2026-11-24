import CoreGraphics
import Darwin

/// Tracks a single left-button drag and decides whether it is a real window drag.
///
/// Classify once at gesture start (title bar + topmost window PID), then require
/// observed AX window movement before snap zones activate. Rejected gestures stay
/// ignored until mouse-up so screenshot / selection drags are never reconsidered
/// as they approach an edge.
struct DragGestureState {
    enum Decision: Equatable {
        case ignore
        case wait
        case detectSnapZone
    }

    private(set) var isActive = false
    private(set) var isCandidate = false

    private var startCursorPosition: CGPoint?
    private var startWindowPosition: CGPoint?
    private var hasConfirmedWindowMovement = false

    mutating func begin(
        isCandidate: Bool,
        cursorPosition: CGPoint,
        windowPosition: CGPoint
    ) {
        reset()
        isActive = true
        self.isCandidate = isCandidate
        startCursorPosition = cursorPosition
        startWindowPosition = windowPosition
    }

    mutating func update(
        cursorPosition: CGPoint,
        currentWindowPosition: CGPoint
    ) -> Decision {
        guard isActive,
              isCandidate,
              let startCursorPosition,
              let startWindowPosition else { return .ignore }

        let cursorDistance = hypot(
            cursorPosition.x - startCursorPosition.x,
            cursorPosition.y - startCursorPosition.y
        )
        guard cursorDistance >= 5 else { return .wait }

        if !hasConfirmedWindowMovement {
            let moved = hypot(
                currentWindowPosition.x - startWindowPosition.x,
                currentWindowPosition.y - startWindowPosition.y
            )
            guard moved >= 5 else { return .wait }
            hasConfirmedWindowMovement = true
        }

        return .detectSnapZone
    }

    mutating func reset() {
        self = DragGestureState()
    }

    /// `point` / `windowPosition` are Accessibility / Quartz coords (Y down).
    static func isPointInTitleBar(
        _ point: CGPoint,
        windowPosition: CGPoint,
        windowSize: CGSize,
        titleBarHeight: CGFloat = 40
    ) -> Bool {
        let relativeY = point.y - windowPosition.y
        return relativeY >= 0
            && relativeY <= titleBarHeight
            && point.x >= windowPosition.x
            && point.x <= windowPosition.x + windowSize.width
    }

    static func isWindowDragCandidate(
        point: CGPoint,
        windowPosition: CGPoint,
        windowSize: CGSize,
        windowPID: pid_t,
        topmostWindowPID: pid_t?
    ) -> Bool {
        isPointInTitleBar(point, windowPosition: windowPosition, windowSize: windowSize)
            && topmostWindowPID == windowPID
    }
}
