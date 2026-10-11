import AppKit
import ApplicationServices
import Foundation

/// Text outside the insertion must remain identical. This rejects navigation,
/// surrounding edits and field replacement instead of guessing which text is ours.
struct InsertionSnapshot {
    let prefix: String
    let suffix: String
    let inserted: String
    init?(before: String, selection: NSRange, inserted: String) {
        let value = before as NSString
        guard before.count <= 16_000, inserted.count <= 4_000, selection.location >= 0,
              selection.length >= 0, selection.location <= value.length,
              selection.length <= value.length - selection.location else { return nil }
        prefix = value.substring(to: selection.location)
        suffix = value.substring(from: selection.location + selection.length)
        self.inserted = inserted
    }
    var expected: String { prefix + inserted + suffix }
    func editedRegion(in text: String) -> String? {
        guard text.count <= 20_000, text.hasPrefix(prefix), text.hasSuffix(suffix),
              text.utf16.count >= prefix.utf16.count + suffix.utf16.count else { return nil }
        let result = (text as NSString).substring(with: NSRange(location: prefix.utf16.count,
            length: text.utf16.count - prefix.utf16.count - suffix.utf16.count))
        return result.count <= 4_000 ? result : nil
    }
}

/// Watches only a verified Murmur insertion, for at most 45 seconds. No global
/// keystroke capture, clipboard sampling, field logging or persisted snapshots.
@MainActor
final class CorrectionLearningMonitor {
    static let shared = CorrectionLearningMonitor()
    struct Target {
        let element: AXUIElement
        let pid: pid_t
        let bundleID: String?
        let snapshot: InsertionSnapshot
    }
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil }

    func capture(inserted: String, expectedPID: pid_t?) -> Target? {
        cancel()
        guard LearnedTermStore.shared.mode != .off,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == expectedPID,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let element = Self.focused(), let value = Self.value(element),
              let selection = Self.selection(element),
              let snapshot = InsertionSnapshot(before: value, selection: selection, inserted: inserted) else { return nil }
        return Target(element: element, pid: app.processIdentifier, bundleID: app.bundleIdentifier, snapshot: snapshot)
    }

    func observe(_ target: Target?) {
        guard let target else { return }
        task = Task { @MainActor in
            // Pasteboard insertion is asynchronous. Arm only after observing the
            // exact inserted content in the original element.
            var verified = false
            for _ in 0..<8 {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard self.isFocused(target), let value = Self.value(target.element) else { return }
                if value == target.snapshot.expected { verified = true; break }
            }
            guard verified else { return }
            var last = target.snapshot.inserted
            var changedAt = Date()
            for _ in 0..<90 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard LearnedTermStore.shared.mode != .off, self.isFocused(target),
                      let value = Self.value(target.element),
                      let region = target.snapshot.editedRegion(in: value) else { return }
                if region != last { last = region; changedAt = Date(); continue }
                guard region != target.snapshot.inserted, !region.isEmpty,
                      Date().timeIntervalSince(changedAt) >= 2 else { continue }
                _ = await LearnedTermStore.shared.learn(before: target.snapshot.inserted, after: region, bundleID: target.bundleID)
                return
            }
        }
    }
    private func isFocused(_ target: Target) -> Bool {
        guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let focused = Self.focused() else { return false }
        return CFEqual(focused, target.element)
    }
    private static func focused() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private static func value(_ element: AXUIElement) -> String? {
        var role: CFTypeRef?, subrole: CFTypeRef?, value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              [kAXTextFieldRole as String, kAXTextAreaRole as String, "AXComboBox"].contains(role as? String ?? "") else { return nil }
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) != kAXSecureTextFieldSubrole as String,
              AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.count <= 20_000 else { return nil }
        return text
    }
    private static func selection(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
