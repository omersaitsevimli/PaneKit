import Carbon
import Carbon.HIToolbox
import Foundation

/// A global hotkey binding: Carbon key code + modifier flags → snap action.
struct HotkeyDefinition: Identifiable {
    let id: UInt32
    let action: SnapAction
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayShortcut: String {
        ShortcutFormatter.displayString(modifiers: carbonModifiers, keyCode: keyCode)
    }

    var isEnabled: Bool {
        carbonModifiers != 0 && keyCode != 0
    }

    /// Resolved bindings (custom overrides applied) for registration / menus.
    static func resolved() -> [HotkeyDefinition] {
        SnapAction.allCases.enumerated().compactMap { index, action in
            let hotkey = UserPreferences.shared.hotkey(for: action)
            return HotkeyDefinition(
                id: UInt32(index + 1),
                action: action,
                keyCode: hotkey.keyCode,
                carbonModifiers: hotkey.modifiers
            )
        }
    }

    /// Built-in defaults (Ctrl+Option base).
    static let defaults: [HotkeyDefinition] = SnapAction.allCases.enumerated().map { index, action in
        let hotkey = action.defaultHotkey
        return HotkeyDefinition(
            id: UInt32(index + 1),
            action: action,
            keyCode: hotkey.keyCode,
            carbonModifiers: hotkey.modifiers
        )
    }
}

extension SnapAction {
    var defaultHotkey: (modifiers: UInt32, keyCode: UInt32) {
        let ctrlOpt = UInt32(controlKey | optionKey)
        let ctrlOptShift = UInt32(controlKey | optionKey | shiftKey)
        let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .leftHalf: return (ctrlOpt, UInt32(kVK_LeftArrow))
        case .rightHalf: return (ctrlOpt, UInt32(kVK_RightArrow))
        case .topHalf: return (ctrlOpt, UInt32(kVK_UpArrow))
        case .bottomHalf: return (ctrlOpt, UInt32(kVK_DownArrow))
        case .topLeft: return (ctrlOpt, UInt32(kVK_ANSI_U))
        case .topRight: return (ctrlOpt, UInt32(kVK_ANSI_I))
        case .bottomLeft: return (ctrlOpt, UInt32(kVK_ANSI_J))
        case .bottomRight: return (ctrlOpt, UInt32(kVK_ANSI_K))
        case .maximize: return (ctrlOpt, UInt32(kVK_Return))
        case .almostMaximize: return (ctrlOpt, UInt32(kVK_ANSI_Equal))
        case .maximizeHeight: return (ctrlOptShift, UInt32(kVK_UpArrow))
        case .smaller: return (ctrlOpt, UInt32(kVK_ANSI_Minus))
        case .larger: return (ctrlOptShift, UInt32(kVK_ANSI_Equal))
        case .center: return (ctrlOpt, UInt32(kVK_ANSI_C))
        case .leftThird: return (ctrlOpt, UInt32(kVK_ANSI_D))
        case .centerThird: return (ctrlOpt, UInt32(kVK_ANSI_F))
        case .rightThird: return (ctrlOpt, UInt32(kVK_ANSI_G))
        case .leftTwoThirds: return (ctrlOpt, UInt32(kVK_ANSI_E))
        case .centerTwoThirds: return (ctrlOpt, UInt32(kVK_ANSI_R))
        case .rightTwoThirds: return (ctrlOpt, UInt32(kVK_ANSI_T))
        case .restore: return (ctrlOpt, UInt32(kVK_Delete))
        case .nextDisplay: return (ctrlOptCmd, UInt32(kVK_RightArrow))
        case .previousDisplay: return (ctrlOptCmd, UInt32(kVK_LeftArrow))
        case .tileRows: return (ctrlOpt, UInt32(kVK_ANSI_Comma))
        case .tileColumns: return (ctrlOpt, UInt32(kVK_ANSI_Period))
        case .cycleStacked: return (ctrlOpt, UInt32(kVK_ANSI_RightBracket))
        case .cycleStackedBack: return (ctrlOpt, UInt32(kVK_ANSI_LeftBracket))
        // Fourths (⌃⌥A/S/Z/X). Wider spans are size-cycle only by default (no binding).
        case .firstFourth: return (ctrlOpt, UInt32(kVK_ANSI_A))
        case .secondFourth: return (ctrlOpt, UInt32(kVK_ANSI_S))
        case .thirdFourth: return (ctrlOpt, UInt32(kVK_ANSI_Z))
        case .fourthFourth: return (ctrlOpt, UInt32(kVK_ANSI_X))
        case .firstTwoFourths, .firstThreeFourths, .lastTwoFourths, .lastThreeFourths:
            return (0, 0)
        // Sixths 2×3 (⌃⌥Q/W/O and ;/'/).
        case .topLeftSixth: return (ctrlOpt, UInt32(kVK_ANSI_Q))
        case .topCenterSixth: return (ctrlOpt, UInt32(kVK_ANSI_W))
        case .topRightSixth: return (ctrlOpt, UInt32(kVK_ANSI_O))
        case .bottomLeftSixth: return (ctrlOpt, UInt32(kVK_ANSI_Semicolon))
        case .bottomCenterSixth: return (ctrlOpt, UInt32(kVK_ANSI_Quote))
        case .bottomRightSixth: return (ctrlOpt, UInt32(kVK_ANSI_Slash))
        case .restoreLastWorkspace: return (ctrlOpt, UInt32(kVK_ANSI_P))
        case .stashToggle: return (ctrlOpt, UInt32(kVK_ANSI_Grave))
        case .unstashAll: return (ctrlOptShift, UInt32(kVK_ANSI_Grave))
        }
    }
}

enum ShortcutFormatter {
    static func displayString(modifiers: UInt32, keyCode: UInt32) -> String {
        guard modifiers != 0, keyCode != 0 else { return "—" }
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}
