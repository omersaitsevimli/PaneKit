import Foundation
import CoreGraphics

/// One window placement inside a saved workspace (normalized to that screen's work area).
struct WorkspaceEntry: Codable, Equatable {
    var bundleID: String
    /// Optional title fragment to disambiguate multiple windows of the same app.
    var titleHint: String
    /// Index into left-to-right sorted screens at save time.
    var screenIndex: Int
    /// Origin/size as fractions of the screen work area (0…1).
    var nx: CGFloat
    var ny: CGFloat
    var nw: CGFloat
    var nh: CGFloat
}

/// Named multi-window arrangement that can be restored manually or when a display connects.
struct Workspace: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var entries: [WorkspaceEntry]
    var restoreOnDisplayConnect: Bool
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        entries: [WorkspaceEntry],
        restoreOnDisplayConnect: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.restoreOnDisplayConnect = restoreOnDisplayConnect
        self.updatedAt = updatedAt
    }
}
