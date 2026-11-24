import AppKit
import Foundation
import CoreGraphics

/// Window snap layouts supported by PaneKit.
enum SnapAction: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case almostMaximize
    case maximizeHeight
    case smaller
    case larger
    case center
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case centerTwoThirds
    case rightTwoThirds
    // Horizontal fourths (and wider spans used by size-cycle).
    case firstFourth
    case secondFourth
    case thirdFourth
    case fourthFourth
    case firstTwoFourths
    case firstThreeFourths
    case lastTwoFourths
    case lastThreeFourths
    // 2×3 sixths.
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    case restore
    case nextDisplay
    case previousDisplay
    case tileRows
    case tileColumns
    case cycleStacked
    case cycleStackedBack
    case restoreLastWorkspace
    case stashToggle
    case unstashAll

    var id: String { rawValue }

    var titleTR: String {
        switch self {
        case .leftHalf: return "Sol yarı"
        case .rightHalf: return "Sağ yarı"
        case .topHalf: return "Üst yarı"
        case .bottomHalf: return "Alt yarı"
        case .topLeft: return "Sol üst çeyrek"
        case .topRight: return "Sağ üst çeyrek"
        case .bottomLeft: return "Sol alt çeyrek"
        case .bottomRight: return "Sağ alt çeyrek"
        case .maximize: return "Tam ekran (maximize)"
        case .almostMaximize: return "Neredeyse tam"
        case .maximizeHeight: return "Yüksekliği maksimize"
        case .smaller: return "Küçült"
        case .larger: return "Büyüt"
        case .center: return "Ortala"
        case .leftThird: return "Sol üçte bir"
        case .centerThird: return "Orta üçte bir"
        case .rightThird: return "Sağ üçte bir"
        case .leftTwoThirds: return "Sol üçte iki"
        case .centerTwoThirds: return "Orta üçte iki"
        case .rightTwoThirds: return "Sağ üçte iki"
        case .firstFourth: return "1. çeyrek (sol)"
        case .secondFourth: return "2. çeyrek"
        case .thirdFourth: return "3. çeyrek"
        case .fourthFourth: return "4. çeyrek (sağ)"
        case .firstTwoFourths: return "Sol iki çeyrek"
        case .firstThreeFourths: return "Sol üç çeyrek"
        case .lastTwoFourths: return "Sağ iki çeyrek"
        case .lastThreeFourths: return "Sağ üç çeyrek"
        case .topLeftSixth: return "Sol üst altıda bir"
        case .topCenterSixth: return "Orta üst altıda bir"
        case .topRightSixth: return "Sağ üst altıda bir"
        case .bottomLeftSixth: return "Sol alt altıda bir"
        case .bottomCenterSixth: return "Orta alt altıda bir"
        case .bottomRightSixth: return "Sağ alt altıda bir"
        case .restore: return "Önceki boyuta dön"
        case .nextDisplay: return "Sonraki ekran"
        case .previousDisplay: return "Önceki ekran"
        case .tileRows: return "Satırlara diz"
        case .tileColumns: return "Sütunlara diz"
        case .cycleStacked: return "Yığın pencereler (ileri)"
        case .cycleStackedBack: return "Yığın pencereler (geri)"
        case .restoreLastWorkspace: return "Son workspace’i yükle"
        case .stashToggle: return "Stash aç/kapa"
        case .unstashAll: return "Tüm stash’leri aç"
        }
    }

    var titleEN: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .maximizeHeight: return "Maximize Height"
        case .smaller: return "Smaller"
        case .larger: return "Larger"
        case .center: return "Center"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two-Thirds"
        case .centerTwoThirds: return "Center Two-Thirds"
        case .rightTwoThirds: return "Right Two-Thirds"
        case .firstFourth: return "First Fourth"
        case .secondFourth: return "Second Fourth"
        case .thirdFourth: return "Third Fourth"
        case .fourthFourth: return "Fourth Fourth"
        case .firstTwoFourths: return "First Two Fourths"
        case .firstThreeFourths: return "First Three Fourths"
        case .lastTwoFourths: return "Last Two Fourths"
        case .lastThreeFourths: return "Last Three Fourths"
        case .topLeftSixth: return "Top Left Sixth"
        case .topCenterSixth: return "Top Center Sixth"
        case .topRightSixth: return "Top Right Sixth"
        case .bottomLeftSixth: return "Bottom Left Sixth"
        case .bottomCenterSixth: return "Bottom Center Sixth"
        case .bottomRightSixth: return "Bottom Right Sixth"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        case .tileRows: return "Tile in Rows"
        case .tileColumns: return "Tile in Columns"
        case .cycleStacked: return "Cycle Stacked Windows"
        case .cycleStackedBack: return "Cycle Stacked Windows Backward"
        case .restoreLastWorkspace: return "Restore Last Workspace"
        case .stashToggle: return "Stash / Unstash"
        case .unstashAll: return "Unstash All"
        }
    }

    /// Multi-window actions that do not place a single focused window into a snap tile.
    var isMultiWindowAction: Bool {
        switch self {
        case .tileRows, .tileColumns, .cycleStacked, .cycleStackedBack,
             .restoreLastWorkspace, .stashToggle, .unstashAll:
            return true
        default:
            return false
        }
    }

    var menuTitle: String { "\(titleTR) / \(titleEN)" }

    /// Related sizes cycled when the same shortcut is pressed repeatedly (Rectangle-style).
    var sizeCycleFamily: [SnapAction]? {
        switch self {
        case .leftHalf, .leftTwoThirds, .leftThird:
            return [.leftHalf, .leftTwoThirds, .leftThird]
        case .rightHalf, .rightTwoThirds, .rightThird:
            return [.rightHalf, .rightTwoThirds, .rightThird]
        case .centerTwoThirds, .centerThird:
            return [.centerTwoThirds, .centerThird]
        case .almostMaximize, .maximize:
            return [.almostMaximize, .maximize]
        case .firstFourth, .firstTwoFourths, .firstThreeFourths:
            return [.firstFourth, .firstTwoFourths, .firstThreeFourths]
        case .fourthFourth, .lastTwoFourths, .lastThreeFourths:
            return [.fourthFourth, .lastTwoFourths, .lastThreeFourths]
        case .secondFourth, .thirdFourth:
            return [.secondFourth, .thirdFourth]
        default:
            return nil
        }
    }

    /// Actions that can cycle to the next monitor after the size sequence is exhausted.
    var hasCycleDirection: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeft, .topRight, .bottomLeft, .bottomRight,
             .leftThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
             .firstFourth, .fourthFourth, .firstTwoFourths, .lastTwoFourths,
             .firstThreeFourths, .lastThreeFourths,
             .topLeftSixth, .topRightSixth, .bottomLeftSixth, .bottomRightSixth:
            return true
        default:
            return false
        }
    }

    /// Maximize fills the work area flush (no window gap). Other tiles get gap inset.
    var appliesWindowGap: Bool {
        switch self {
        case .maximize:
            return false
        default:
            return true
        }
    }

    /// Work-area snap rect for `screen`, with window gap applied when appropriate.
    func snappedRect(on screen: NSScreen) -> CGRect? {
        let area = ScreenHelper.workArea(for: screen)
        guard let raw = targetRect(in: area) else { return nil }
        guard appliesWindowGap else { return raw }
        return ScreenHelper.applyWindowGap(raw, gap: UserPreferences.shared.windowGap)
    }

    /// Geometric snap rect in Cocoa coordinates, or `nil` for special actions.
    func targetRect(in visibleFrame: CGRect) -> CGRect? {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let w = visibleFrame.width
        let h = visibleFrame.height
        let halfW = floor(w / 2)
        let halfH = floor(h / 2)
        let thirdW = floor(w / 3)
        let twoThirdsW = thirdW * 2
        let fourthW = floor(w / 4)
        let twoFourthsW = fourthW * 2
        let threeFourthsW = fourthW * 3
        let sixthW = floor(w / 3)
        let inset = UserPreferences.shared.almostMaximizeInset

        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: h)
        case .topHalf:
            return CGRect(x: x, y: y + halfH, width: w, height: h - halfH)
        case .bottomHalf:
            return CGRect(x: x, y: y, width: w, height: halfH)
        case .topLeft:
            return CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH)
        case .topRight:
            return CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH)
        case .bottomLeft:
            return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH)
        case .maximize:
            return visibleFrame
        case .almostMaximize:
            return CGRect(
                x: x + inset,
                y: y + inset,
                width: w - inset * 2,
                height: h - inset * 2
            )
        case .leftThird:
            return CGRect(x: x, y: y, width: thirdW, height: h)
        case .centerThird:
            return CGRect(x: x + thirdW, y: y, width: thirdW, height: h)
        case .rightThird:
            return CGRect(x: x + twoThirdsW, y: y, width: w - twoThirdsW, height: h)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: twoThirdsW, height: h)
        case .centerTwoThirds:
            let sixth = floor(w / 6)
            return CGRect(x: x + sixth, y: y, width: w - sixth * 2, height: h)
        case .rightTwoThirds:
            return CGRect(x: x + thirdW, y: y, width: w - thirdW, height: h)
        case .firstFourth:
            return CGRect(x: x, y: y, width: fourthW, height: h)
        case .secondFourth:
            return CGRect(x: x + fourthW, y: y, width: fourthW, height: h)
        case .thirdFourth:
            return CGRect(x: x + twoFourthsW, y: y, width: fourthW, height: h)
        case .fourthFourth:
            return CGRect(x: x + threeFourthsW, y: y, width: w - threeFourthsW, height: h)
        case .firstTwoFourths:
            return CGRect(x: x, y: y, width: twoFourthsW, height: h)
        case .firstThreeFourths:
            return CGRect(x: x, y: y, width: threeFourthsW, height: h)
        case .lastTwoFourths:
            return CGRect(x: x + twoFourthsW, y: y, width: w - twoFourthsW, height: h)
        case .lastThreeFourths:
            return CGRect(x: x + fourthW, y: y, width: w - fourthW, height: h)
        case .topLeftSixth:
            return CGRect(x: x, y: y + halfH, width: sixthW, height: h - halfH)
        case .topCenterSixth:
            return CGRect(x: x + sixthW, y: y + halfH, width: sixthW, height: h - halfH)
        case .topRightSixth:
            return CGRect(x: x + sixthW * 2, y: y + halfH, width: w - sixthW * 2, height: h - halfH)
        case .bottomLeftSixth:
            return CGRect(x: x, y: y, width: sixthW, height: halfH)
        case .bottomCenterSixth:
            return CGRect(x: x + sixthW, y: y, width: sixthW, height: halfH)
        case .bottomRightSixth:
            return CGRect(x: x + sixthW * 2, y: y, width: w - sixthW * 2, height: halfH)
        case .center, .restore, .nextDisplay, .previousDisplay,
             .maximizeHeight, .smaller, .larger,
             .tileRows, .tileColumns, .cycleStacked, .cycleStackedBack,
             .restoreLastWorkspace, .stashToggle, .unstashAll:
            return nil
        }
    }

    /// Horizontally (or vertically for top/bottom half) mirrored action for monitor cycling.
    var mirrored: SnapAction {
        switch self {
        case .leftHalf: return .rightHalf
        case .rightHalf: return .leftHalf
        case .topLeft: return .topRight
        case .topRight: return .topLeft
        case .bottomLeft: return .bottomRight
        case .bottomRight: return .bottomLeft
        case .leftThird: return .rightThird
        case .rightThird: return .leftThird
        case .leftTwoThirds: return .rightTwoThirds
        case .rightTwoThirds: return .leftTwoThirds
        case .topHalf: return .bottomHalf
        case .bottomHalf: return .topHalf
        case .firstFourth: return .fourthFourth
        case .secondFourth: return .thirdFourth
        case .thirdFourth: return .secondFourth
        case .fourthFourth: return .firstFourth
        case .firstTwoFourths: return .lastTwoFourths
        case .firstThreeFourths: return .lastThreeFourths
        case .lastTwoFourths: return .firstTwoFourths
        case .lastThreeFourths: return .firstThreeFourths
        case .topLeftSixth: return .topRightSixth
        case .topRightSixth: return .topLeftSixth
        case .bottomLeftSixth: return .bottomRightSixth
        case .bottomRightSixth: return .bottomLeftSixth
        case .topCenterSixth: return .topCenterSixth
        case .bottomCenterSixth: return .bottomCenterSixth
        default: return self
        }
    }

    /// +1 = next (rightward) screen, -1 = previous.
    var cycleDirection: Int {
        switch self {
        case .rightHalf, .topRight, .bottomRight, .rightThird, .rightTwoThirds, .bottomHalf,
             .fourthFourth, .lastTwoFourths, .lastThreeFourths,
             .topRightSixth, .bottomRightSixth:
            return 1
        case .leftHalf, .topLeft, .bottomLeft, .leftThird, .leftTwoThirds, .topHalf,
             .firstFourth, .firstTwoFourths, .firstThreeFourths,
             .topLeftSixth, .bottomLeftSixth:
            return -1
        default:
            return 1
        }
    }
}
