import AppKit
import Carbon.HIToolbox

struct AppShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let `default` = AppShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        label: "⌥Space"
    )

    static let expandDefault = AppShortcut(
        keyCode: UInt32(kVK_Return),
        modifiers: UInt32(cmdKey),
        label: "⌘↩"
    )

    static let sidebarDefault = AppShortcut(
        keyCode: UInt32(kVK_ANSI_Backslash),
        modifiers: UInt32(cmdKey),
        label: "⌘\\"
    )

    var displayString: String {
        label.isEmpty ? Self.display(keyCode: keyCode, modifiers: modifiers) : label
    }

    var isValid: Bool {
        !Self.modifierSymbols(modifiers).isEmpty || Self.isFunctionKey(keyCode)
    }

    var carbonModifiers: UInt32 { modifiers }

    static func from(event: NSEvent) -> AppShortcut? {
        let carbon = carbonModifiers(from: event)
        let keyCode = UInt32(event.keyCode)
        let candidate = AppShortcut(
            keyCode: keyCode,
            modifiers: carbon,
            label: display(keyCode: keyCode, modifiers: carbon, characters: event.charactersIgnoringModifiers)
        )
        return candidate.isValid ? candidate : nil
    }

    func matches(event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode && Self.carbonModifiers(from: event) == modifiers
    }

    private static func carbonModifiers(from event: NSEvent) -> UInt32 {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    static func display(
        keyCode: UInt32,
        modifiers: UInt32,
        characters: String? = nil
    ) -> String {
        let prefix = modifierSymbols(modifiers)
        let key = keyName(keyCode: keyCode, characters: characters)
        return prefix + key
    }

    private static func modifierSymbols(_ modifiers: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value
    }

    private static func keyName(keyCode: UInt32, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
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
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Keypad0: return "Num 0"
        case kVK_ANSI_Keypad1: return "Num 1"
        case kVK_ANSI_Keypad2: return "Num 2"
        case kVK_ANSI_Keypad3: return "Num 3"
        case kVK_ANSI_Keypad4: return "Num 4"
        case kVK_ANSI_Keypad5: return "Num 5"
        case kVK_ANSI_Keypad6: return "Num 6"
        case kVK_ANSI_Keypad7: return "Num 7"
        case kVK_ANSI_Keypad8: return "Num 8"
        case kVK_ANSI_Keypad9: return "Num 9"
        default:
            if let characters, !characters.isEmpty {
                return characters.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        let functionKeys: Set<Int> = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
            kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        return functionKeys.contains(Int(keyCode))
    }
}
