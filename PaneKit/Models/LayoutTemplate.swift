import Foundation
import CoreGraphics

/// A single zone inside a multi-window layout (normalized 0…1 Cocoa space).
struct LayoutZone: Identifiable, Hashable {
    let id: String
    /// Fraction of the screen `visibleFrame` (origin bottom-left).
    let rect: CGRect

    func absoluteRect(in visibleFrame: CGRect) -> CGRect {
        let x = floor(visibleFrame.origin.x + rect.origin.x * visibleFrame.width)
        let y = floor(visibleFrame.origin.y + rect.origin.y * visibleFrame.height)
        let maxX = floor(visibleFrame.origin.x + (rect.origin.x + rect.width) * visibleFrame.width)
        let maxY = floor(visibleFrame.origin.y + (rect.origin.y + rect.height) * visibleFrame.height)
        return CGRect(x: x, y: y, width: max(1, maxX - x), height: max(1, maxY - y))
    }
}

/// A Windows 11–style snap layout template made of one or more zones.
struct LayoutTemplate: Identifiable, Hashable {
    let id: String
    let titleTR: String
    let titleEN: String
    let zones: [LayoutZone]

    var title: String { titleTR }

    static let all: [LayoutTemplate] = [
        .verticalHalves,
        .horizontalHalves,
        .leftTwoThirdsRightStack,
        .rightTwoThirdsLeftStack,
        .threeColumns,
        .fourQuarters,
        .leftThirdRightTwoThirds,
        .leftTwoThirdsRightThird,
    ]

    // MARK: - Templates

    static let verticalHalves = LayoutTemplate(
        id: "verticalHalves",
        titleTR: "Dikey yarılar",
        titleEN: "Vertical halves",
        zones: [
            LayoutZone(id: "left", rect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            LayoutZone(id: "right", rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]
    )

    static let horizontalHalves = LayoutTemplate(
        id: "horizontalHalves",
        titleTR: "Yatay yarılar",
        titleEN: "Horizontal halves",
        zones: [
            LayoutZone(id: "top", rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)),
            LayoutZone(id: "bottom", rect: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
        ]
    )

    static let leftTwoThirdsRightStack = LayoutTemplate(
        id: "leftTwoThirdsRightStack",
        titleTR: "Sol ⅔ + sağ yığın",
        titleEN: "Left ⅔ + right stack",
        zones: [
            LayoutZone(id: "left", rect: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)),
            LayoutZone(id: "rightTop", rect: CGRect(x: 2.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5)),
            LayoutZone(id: "rightBottom", rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.5)),
        ]
    )

    static let rightTwoThirdsLeftStack = LayoutTemplate(
        id: "rightTwoThirdsLeftStack",
        titleTR: "Sağ ⅔ + sol yığın",
        titleEN: "Right ⅔ + left stack",
        zones: [
            LayoutZone(id: "leftTop", rect: CGRect(x: 0, y: 0.5, width: 1.0 / 3.0, height: 0.5)),
            LayoutZone(id: "leftBottom", rect: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 0.5)),
            LayoutZone(id: "right", rect: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)),
        ]
    )

    static let threeColumns = LayoutTemplate(
        id: "threeColumns",
        titleTR: "Üç sütun",
        titleEN: "Three columns",
        zones: [
            LayoutZone(id: "left", rect: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)),
            LayoutZone(id: "center", rect: CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
            LayoutZone(id: "right", rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
        ]
    )

    static let fourQuarters = LayoutTemplate(
        id: "fourQuarters",
        titleTR: "Dört çeyrek",
        titleEN: "Four quarters",
        zones: [
            LayoutZone(id: "topLeft", rect: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            LayoutZone(id: "topRight", rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            LayoutZone(id: "bottomLeft", rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            LayoutZone(id: "bottomRight", rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        ]
    )

    static let leftThirdRightTwoThirds = LayoutTemplate(
        id: "leftThirdRightTwoThirds",
        titleTR: "Sol ⅓ + sağ ⅔",
        titleEN: "Left ⅓ + right ⅔",
        zones: [
            LayoutZone(id: "left", rect: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)),
            LayoutZone(id: "right", rect: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)),
        ]
    )

    static let leftTwoThirdsRightThird = LayoutTemplate(
        id: "leftTwoThirdsRightThird",
        titleTR: "Sol ⅔ + sağ ⅓",
        titleEN: "Left ⅔ + right ⅓",
        zones: [
            LayoutZone(id: "left", rect: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)),
            LayoutZone(id: "right", rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
        ]
    )

    /// All zone frames for a template with shared seams (no overlap at the midline).
    func zoneFrames(in visibleFrame: CGRect) -> [String: CGRect] {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let w = visibleFrame.width
        let h = visibleFrame.height
        let halfW = floor(w / 2)
        let halfH = floor(h / 2)
        let thirdW = floor(w / 3)
        let twoThirdsW = thirdW * 2

        switch id {
        case "verticalHalves":
            return [
                "left": CGRect(x: x, y: y, width: halfW, height: h),
                "right": CGRect(x: x + halfW, y: y, width: w - halfW, height: h),
            ]
        case "horizontalHalves":
            return [
                "bottom": CGRect(x: x, y: y, width: w, height: halfH),
                "top": CGRect(x: x, y: y + halfH, width: w, height: h - halfH),
            ]
        case "threeColumns":
            return [
                "left": CGRect(x: x, y: y, width: thirdW, height: h),
                "center": CGRect(x: x + thirdW, y: y, width: thirdW, height: h),
                "right": CGRect(x: x + twoThirdsW, y: y, width: w - twoThirdsW, height: h),
            ]
        case "fourQuarters":
            return [
                "topLeft": CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH),
                "topRight": CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH),
                "bottomLeft": CGRect(x: x, y: y, width: halfW, height: halfH),
                "bottomRight": CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH),
            ]
        case "leftTwoThirdsRightStack":
            return [
                "left": CGRect(x: x, y: y, width: twoThirdsW, height: h),
                "rightTop": CGRect(x: x + twoThirdsW, y: y + halfH, width: w - twoThirdsW, height: h - halfH),
                "rightBottom": CGRect(x: x + twoThirdsW, y: y, width: w - twoThirdsW, height: halfH),
            ]
        case "rightTwoThirdsLeftStack":
            return [
                "leftTop": CGRect(x: x, y: y + halfH, width: thirdW, height: h - halfH),
                "leftBottom": CGRect(x: x, y: y, width: thirdW, height: halfH),
                "right": CGRect(x: x + thirdW, y: y, width: w - thirdW, height: h),
            ]
        case "leftThirdRightTwoThirds":
            return [
                "left": CGRect(x: x, y: y, width: thirdW, height: h),
                "right": CGRect(x: x + thirdW, y: y, width: w - thirdW, height: h),
            ]
        case "leftTwoThirdsRightThird":
            return [
                "left": CGRect(x: x, y: y, width: twoThirdsW, height: h),
                "right": CGRect(x: x + twoThirdsW, y: y, width: w - twoThirdsW, height: h),
            ]
        default:
            return Dictionary(uniqueKeysWithValues: zones.map { ($0.id, $0.absoluteRect(in: visibleFrame)) })
        }
    }
}
