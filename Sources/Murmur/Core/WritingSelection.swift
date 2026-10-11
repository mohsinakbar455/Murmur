import AppKit
import ApplicationServices

/// Range units are UTF-16 throughout, matching the macOS accessibility contract.
struct WritingSelectionFingerprint: Equatable {
    let text: String
    let range: NSRange
    func matches(text: String, range: NSRange) -> Bool { self.text == text && self.range == range }
    func replacementRange(for text: String) -> NSRange {
        NSRange(location: range.location, length: (text as NSString).length)
    }
}

@MainActor
struct WritingSelection {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let fingerprint: WritingSelectionFingerprint
    var usesClipboard = false
    var lease: WritingSelectionLease?
    var window: AXUIElement?

    struct Receipt {
        let selection: WritingSelection
        let replacement: String
        let range: NSRange
        let caret: NSRange
    }
    enum Delivery {
        case applied(Receipt)
        case unchanged
        case unavailable
        case unverified
        case dispatched
    }

    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func focused(in pid: pid_t) -> AXUIElement? {
        if let raw = attribute(kAXFocusedUIElementAttribute, of: AXUIElementCreateApplication(pid)),
           CFGetTypeID(raw) == AXUIElementGetTypeID() {
            return unsafeDowncast(raw, to: AXUIElement.self)
        }
        guard let raw = attribute(kAXFocusedUIElementAttribute, of: AXUIElementCreateSystemWide()),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(raw, to: AXUIElement.self)
        var elementPID: pid_t = 0
        return AXUIElementGetPid(element, &elementPID) == .success && elementPID == pid ? element : nil
    }

    static func isTextEntry(_ element: AXUIElement) -> Bool {
        guard attribute(kAXEnabledAttribute, of: element) as? Bool != false else { return false }
        let role = attribute(kAXRoleAttribute, of: element) as? String
        if isTextEntry(role: role, editable: attribute("AXEditable", of: element) as? Bool == true) { return true }
        // Some custom editors expose writable text without a standard text-field role.
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    static func isTextEntry(role: String?, editable: Bool) -> Bool {
        editable || role == "AXSearchField" || role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
            || role == kAXComboBoxRole as String
    }

    /// Browser editors often focus a tiny offscreen input. Use its first visible ancestor
    /// for the launcher while keeping the focused input itself for guarded text operations.
    static func launcherFrame(of element: AXUIElement, in pid: pid_t) -> CGRect? {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            if let frame = frame(of: node), NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return frame }
            guard let parent = attribute(kAXParentAttribute, of: node),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        let app = AXUIElementCreateApplication(pid)
        for window in [attribute(kAXWindowAttribute, of: element), attribute(kAXFocusedWindowAttribute, of: app)] {
            if let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
               let frame = frame(of: unsafeDowncast(window, to: AXUIElement.self)) { return frame }
        }
        return nil
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        // Include ancestors: web editors can expose a child inside a secure control.
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            if attribute(kAXSubroleAttribute, of: node) as? String == kAXSecureTextFieldSubrole as String { return true }
            guard let parent = attribute(kAXParentAttribute, of: node), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }

    static func range(of element: AXUIElement) -> NSRange? {
        guard let raw = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func text(in range: NSRange, of element: AXUIElement) -> String? {
        if range.length == 0 { return "" }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var raw: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &raw) == .success,
           let text = raw as? String { return text }
        // Used only on explicit capture/apply/Undo, never by background geometry tracking.
        guard let value = attribute(kAXValueAttribute, of: element) as? String else { return nil }
        let string = value as NSString
        guard range.location <= string.length, range.length <= string.length - range.location else { return nil }
        return string.substring(with: range)
    }

    static func selectedText(of element: AXUIElement, range: NSRange) -> String? {
        if range.length == 0 { return "" }
        return (attribute(kAXSelectedTextAttribute, of: element) as? String) ?? text(in: range, of: element)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(kAXSizeAttribute, of: element), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              dimensions.width >= 60, dimensions.height >= 24 else { return nil }
        // AX uses a top-left screen origin; AppKit uses the primary display's bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: origin.x, y: primaryHeight - origin.y - dimensions.height, width: dimensions.width, height: dimensions.height)
    }

    enum CaptureRoute { case accessibility, clipboard }

    static func captureRoute(hasFrame: Bool, range: NSRange?, text: String?) -> CaptureRoute {
        guard hasFrame, let range, let text,
              (text as NSString).length == range.length else { return .clipboard }
        return .accessibility
    }

    static func capture(element: AXUIElement, app: NSRunningApplication) -> WritingSelection? {
        guard !isSecure(element), let range = range(of: element),
              range.length <= WritingAssistantService.maximumSourceLength,
              let text = selectedText(of: element, range: range), (text as NSString).length == range.length else { return nil }
        return WritingSelection(element: element, pid: app.processIdentifier, appName: app.localizedName ?? "Editor", bundleID: app.bundleIdentifier,
            fingerprint: .init(text: text, range: range))
    }

    static func captureAutomatically(element: AXUIElement, app: NSRunningApplication) async -> WritingSelection? {
        guard !isSecure(element) else { return nil }
        let direct = capture(element: element, app: app)
        let route = captureRoute(hasFrame: frame(of: element) != nil,
                                 range: direct?.fingerprint.range, text: direct?.fingerprint.text)
        if route == .accessibility { return direct }
        let lease = WritingSelectionLease(pid: app.processIdentifier)
        let rawWindow = attribute(kAXWindowAttribute, of: element)
        let window = rawWindow.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeDowncast($0, to: AXUIElement.self) : nil }
        var selection = WritingSelection(element: element, pid: app.processIdentifier,
            appName: app.localizedName ?? "Editor", bundleID: app.bundleIdentifier,
            fingerprint: .init(text: "", range: NSRange(location: 0, length: 0)), usesClipboard: true, lease: lease, window: window)
        guard let text = await WritingClipboard.readSelection(isCurrent: { selection.hasFocus() && !lease.changed }) else {
            lease.stop()
            // A genuine empty native field is still a destination for Compose.
            return frame(of: element) != nil ? direct : nil
        }
        selection = WritingSelection(element: element, pid: app.processIdentifier,
            appName: app.localizedName ?? "Editor", bundleID: app.bundleIdentifier,
            fingerprint: .init(text: text, range: NSRange(location: 0, length: (text as NSString).length)),
            usesClipboard: true, lease: lease, window: window)
        return selection
    }

    private func hasFocus() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = Self.focused(in: pid), CFEqual(focused, element), !Self.isSecure(element) else { return false }
        if let window {
            guard let current = Self.attribute(kAXFocusedWindowAttribute, of: AXUIElementCreateApplication(pid)),
                  CFEqual(window, current) else { return false }
        }
        return lease?.changed != true
    }

    /// Hiding a key-capable assistant panel takes a run-loop turn to restore the
    /// editor's keyboard focus. Wait for it, without forcing a different field.
    func waitForFocus() async -> Bool {
        for _ in 0..<10 {
            guard !Task.isCancelled, lease?.changed != true else { return false }
            if hasFocus() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    func isCurrent() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = Self.focused(in: pid), CFEqual(focused, element), !Self.isSecure(element),
              let range = Self.range(of: element), let text = Self.selectedText(of: element, range: range) else { return false }
        return fingerprint.matches(text: text, range: range)
    }

    /// A write is never retried unless the original selection can still be observed intact.
    func replace(with replacement: String) async -> Delivery {
        guard !Task.isCancelled else { return .unavailable }
        if usesClipboard {
            guard hasFocus() else { return .unavailable }
            if replacement == fingerprint.text { return .unchanged }
            let sent = await WritingClipboard.replaceSelection(fingerprint.text, with: replacement, isCurrent: { hasFocus() })
            return sent ? .dispatched : .unavailable
        }
        guard isCurrent() else { return .unavailable }
        if replacement == fingerprint.text { return .unchanged }
        let insertedRange = fingerprint.replacementRange(for: replacement)
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue {
            let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
            if status == .success {
                try? await Task.sleep(for: .milliseconds(100))
                if let receipt = receipt(for: replacement, range: insertedRange) { return .applied(receipt) }
                guard isCurrent() else { return .unverified }
            }
        }
        guard !Task.isCancelled, isCurrent() else { return .unavailable }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        pasteboard.clearContents()
        pasteboard.setString(replacement, forType: .string)
        let changeCount = pasteboard.changeCount
        // Restoration is independent of generation cancellation, and never overwrites a newer copy.
        defer {
            if Settings.shared.preserveClipboard && pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                let items = (saved ?? []).map { entry in
                    let item = NSPasteboardItem()
                    for (type, data) in entry { item.setData(data, forType: type) }
                    return item
                }
                pasteboard.writeObjects(items)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, isCurrent(), pasteboard.changeCount == changeCount,
              let eventSource = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 9, keyDown: false) else { return .unavailable }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Once dispatched, let the editor consume the clipboard even if Cancel is pressed.
        await Task.detached { try? await Task.sleep(for: .milliseconds(600)) }.value
        if let receipt = receipt(for: replacement, range: insertedRange) { return .applied(receipt) }
        return .unverified
    }

    private func receipt(for replacement: String, range: NSRange) -> Receipt? {
        guard let caret = Self.range(of: element), (caret == range || caret == NSRange(location: NSMaxRange(range), length: 0)),
              Self.text(in: range, of: element) == replacement else { return nil }
        return Receipt(selection: self, replacement: replacement, range: range, caret: caret)
    }

    static func canUndo(_ receipt: Receipt) -> Bool {
        let selection = receipt.selection
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.pid,
              let focused = focused(in: selection.pid), CFEqual(focused, selection.element), !isSecure(selection.element),
              range(of: selection.element) == receipt.caret else { return false }
        return text(in: receipt.range, of: selection.element) == receipt.replacement
    }

    static func undo(_ receipt: Receipt) async -> Delivery {
        guard canUndo(receipt) else { return .unavailable }
        var range = CFRange(location: receipt.range.location, length: receipt.range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(receipt.selection.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return .unavailable }
        let reverse = WritingSelection(element: receipt.selection.element, pid: receipt.selection.pid,
            appName: receipt.selection.appName, bundleID: receipt.selection.bundleID,
            fingerprint: .init(text: receipt.replacement, range: receipt.range))
        return await reverse.replace(with: receipt.selection.fingerprint.text)
    }
}
