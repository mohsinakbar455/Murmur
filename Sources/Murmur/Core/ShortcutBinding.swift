import AppKit
import Carbon.HIToolbox
import Foundation

/// Modifiers that can be required in a key combination.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0) // ⌘
    public static let option  = ShortcutModifiers(rawValue: 1 << 1) // ⌥
    public static let control = ShortcutModifiers(rawValue: 1 << 2) // ⌃
    public static let shift   = ShortcutModifiers(rawValue: 1 << 3) // ⇧

    public init(cgFlags: CGEventFlags) {
        var mods: ShortcutModifiers = []
        if cgFlags.contains(.maskCommand) { mods.insert(.command) }
        if cgFlags.contains(.maskAlternate) { mods.insert(.option) }
        if cgFlags.contains(.maskControl) { mods.insert(.control) }
        if cgFlags.contains(.maskShift) { mods.insert(.shift) }
        self = mods
    }

    public init(nsFlags: NSEvent.ModifierFlags) {
        var mods: ShortcutModifiers = []
        if nsFlags.contains(.command) { mods.insert(.command) }
        if nsFlags.contains(.option) { mods.insert(.option) }
        if nsFlags.contains(.control) { mods.insert(.control) }
        if nsFlags.contains(.shift) { mods.insert(.shift) }
        self = mods
    }

    public var displayGlyphs: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option)  { result += "⌥" }
        if contains(.shift)   { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    public var cgEventFlagsMask: CGEventFlags {
        var flags = CGEventFlags()
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    public func matches(cgFlags: CGEventFlags) -> Bool {
        let current = ShortcutModifiers(cgFlags: cgFlags)
        return current == self
    }

    public func isSatisfied(by cgFlags: CGEventFlags) -> Bool {
        let current = ShortcutModifiers(cgFlags: cgFlags)
        return self.isSubset(of: current)
    }
}

/// Specific physical modifier keys, distinguishing left and right sides.
public enum SpecificModifierKey: String, Codable, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case fn
    case rightControl
    case leftOption
    case leftCommand
    case leftControl
    case rightShift
    case leftShift

    public var keyCode: Int64 {
        switch self {
        case .rightOption:  return Int64(kVK_RightOption)   // 61
        case .rightCommand: return Int64(kVK_RightCommand)  // 54
        case .fn:           return Int64(kVK_Function)      // 63
        case .rightControl: return Int64(kVK_RightControl)  // 62
        case .leftOption:   return Int64(kVK_Option)        // 58
        case .leftCommand:  return Int64(kVK_Command)       // 55
        case .leftControl:  return Int64(kVK_Control)       // 59
        case .rightShift:   return Int64(kVK_RightShift)    // 60
        case .leftShift:    return Int64(kVK_Shift)         // 56
        }
    }

    /// Device-dependent raw mask distinguishing left/right physical keys.
    public var flag: CGEventFlags {
        switch self {
        case .rightOption:  return CGEventFlags(rawValue: 0x40)    // NX_DEVICERALTKEYMASK
        case .rightCommand: return CGEventFlags(rawValue: 0x10)    // NX_DEVICERCMDKEYMASK
        case .fn:           return .maskSecondaryFn
        case .rightControl: return CGEventFlags(rawValue: 0x2000)  // NX_DEVICERCTLKEYMASK
        case .leftOption:   return CGEventFlags(rawValue: 0x20)    // NX_DEVICELALTKEYMASK
        case .leftCommand:  return CGEventFlags(rawValue: 0x08)    // NX_DEVICELCMDKEYMASK
        case .leftControl:  return CGEventFlags(rawValue: 0x01)    // NX_DEVICELCTLKEYMASK
        case .rightShift:   return CGEventFlags(rawValue: 0x04)    // NX_DEVICERSHIFTKEYMASK
        case .leftShift:    return CGEventFlags(rawValue: 0x02)    // NX_DEVICELSHIFTKEYMASK
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption:  return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .fn:           return "fn"
        case .rightControl: return "Right ⌃"
        case .leftOption:   return "Left ⌥"
        case .leftCommand:  return "Left ⌘"
        case .leftControl:  return "Left ⌃"
        case .rightShift:   return "Right ⇧"
        case .leftShift:    return "Left ⇧"
        }
    }

    public var shouldConsumeEvent: Bool {
        // Swallowing fn breaks system functions (fn+arrows, emoji), so let it through.
        self != .fn
    }
}

/// Versioned, persistent representation of a user-configurable push-to-talk shortcut.
public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case modifierOnly
        case keyCombination
    }

    public var version: Int
    public var kind: Kind
    public var specificModifier: SpecificModifierKey?
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers

    public init(
        version: Int = 1,
        kind: Kind,
        specificModifier: SpecificModifierKey? = nil,
        keyCode: UInt16 = 0,
        modifiers: ShortcutModifiers = []
    ) {
        self.version = version
        self.kind = kind
        self.specificModifier = specificModifier
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: - Presets

    public static let rightOption = ShortcutBinding(
        kind: .modifierOnly,
        specificModifier: .rightOption,
        keyCode: UInt16(kVK_RightOption)
    )

    public static let rightCommand = ShortcutBinding(
        kind: .modifierOnly,
        specificModifier: .rightCommand,
        keyCode: UInt16(kVK_RightCommand)
    )

    public static let fn = ShortcutBinding(
        kind: .modifierOnly,
        specificModifier: .fn,
        keyCode: UInt16(kVK_Function)
    )

    public static let defaultBinding = ShortcutBinding.rightOption

    // MARK: - Display

    public var displayName: String {
        switch kind {
        case .modifierOnly:
            return specificModifier?.displayName ?? "Modifier"
        case .keyCombination:
            let keyStr = Self.stringForKeyCode(keyCode)
            return "\(modifiers.displayGlyphs)\(keyStr)"
        }
    }

    public var keycapTokens: [String] {
        switch kind {
        case .modifierOnly:
            guard let specific = specificModifier else { return ["Key"] }
            switch specific {
            case .rightOption:  return ["Right", "⌥"]
            case .rightCommand: return ["Right", "⌘"]
            case .fn:           return ["fn"]
            case .rightControl: return ["Right", "⌃"]
            case .leftOption:   return ["Left", "⌥"]
            case .leftCommand:  return ["Left", "⌘"]
            case .leftControl:  return ["Left", "⌃"]
            case .rightShift:   return ["Right", "⇧"]
            case .leftShift:    return ["Left", "⇧"]
            }
        case .keyCombination:
            var tokens: [String] = []
            if modifiers.contains(.control) { tokens.append("⌃") }
            if modifiers.contains(.option)  { tokens.append("⌥") }
            if modifiers.contains(.shift)   { tokens.append("⇧") }
            if modifiers.contains(.command) { tokens.append("⌘") }
            tokens.append(Self.stringForKeyCode(keyCode))
            return tokens
        }
    }

    // MARK: - Validation

    public enum ValidationError: LocalizedError, Equatable {
        case empty
        case bareTypingKey(String)
        case shiftOnly(String)
        case escapeForbidden
        case reservedSystemKey

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Press a key combination to set a shortcut."
            case .bareTypingKey(let key):
                return "Bare '\(key)' cannot be used as a global shortcut. Hold at least ⌃, ⌥, or ⌘."
            case .shiftOnly(let key):
                return "Shift alone with '\(key)' would interfere with regular typing. Add ⌃, ⌥, or ⌘."
            case .escapeForbidden:
                return "Escape is reserved for canceling operations."
            case .reservedSystemKey:
                return "This combination is reserved by macOS."
            }
        }
    }

    public func validate() -> Result<Void, ValidationError> {
        switch kind {
        case .modifierOnly:
            if specificModifier != nil {
                return .success(())
            }
            return .failure(.empty)

        case .keyCombination:
            if keyCode == kVK_Escape {
                return .failure(.escapeForbidden)
            }

            let keyStr = Self.stringForKeyCode(keyCode)

            // Allow function keys (F1-F19) even without modifiers if pressed
            let isFunctionKey = (keyCode >= 122 && keyCode <= 120) || // F1-F8 range
                (keyCode == 96 || keyCode == 97 || keyCode == 98 || keyCode == 99 || keyCode == 100 || keyCode == 101) || // F5-F10
                (keyCode >= 109 && keyCode <= 113) || (keyCode == 105 || keyCode == 107) || // F11-F19
                (keyCode >= kVK_F1 && keyCode <= kVK_F12)

            let hasSubstantiveModifier = modifiers.contains(.command) ||
                                         modifiers.contains(.option) ||
                                         modifiers.contains(.control)

            if !hasSubstantiveModifier && !isFunctionKey {
                if modifiers.contains(.shift) {
                    return .failure(.shiftOnly(keyStr))
                }
                return .failure(.bareTypingKey(keyStr))
            }

            return .success(())
        }
    }

    // MARK: - Legacy Migration

    public static func migrate(from legacyKeyString: String?) -> ShortcutBinding {
        guard let legacyKeyString else { return .defaultBinding }
        switch legacyKeyString {
        case "rightOption":
            return .rightOption
        case "fn":
            return .fn
        case "rightCommand":
            return .rightCommand
        default:
            return .defaultBinding
        }
    }

    // MARK: - Keycode translation

    public static func stringForKeyCode(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "Esc"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"

        // Function keys
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

        // Common ANSI keys fallback
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

        default:
            // Dynamic translation from current input source
            if let str = translateVirtualKeyCode(keyCode) {
                return str.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private static func translateVirtualKeyCode(_ keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let layoutPtr = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let uchrHeader = layoutPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        var actualStringLength = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            uchrHeader,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualStringLength,
            &chars
        )

        if status == noErr && actualStringLength > 0 {
            return String(utf16CodeUnits: chars, count: actualStringLength)
        }
        return nil
    }
}
