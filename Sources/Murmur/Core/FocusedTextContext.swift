import AppKit
import ApplicationServices

/// Opt-in bounded field context. Secure controls are never read.
@MainActor
enum FocusedTextContext {
    static func read() -> String? {
        guard Settings.shared.readFieldContext else { return nil }
        let system = AXUIElementCreateSystemWide()
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let field = unsafeDowncast(raw, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) != kAXSecureTextFieldSubrole as String else { return nil }
        var value: CFTypeRef?, rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rangeValue, to: AXValue.self), .cfRange, &range) else { return nil }
        let utf16 = text as NSString
        let end = min(max(0, range.location), utf16.length)
        return utf16.substring(with: NSRange(location: max(0, end - 240), length: min(240, end)))
    }
}
