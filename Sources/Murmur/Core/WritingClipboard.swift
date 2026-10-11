import AppKit

/// A short clipboard lease used only after the user opens or applies an edit.
/// Selection reads require a fresh Copy response; an old clipboard is never source text.
@MainActor
enum WritingClipboard {
    static let eventTag: Int64 = 0x4D555257
    private static var leased = false
    private static let markerType = NSPasteboard.PasteboardType("ai.pivotstudio.murmur.selection-probe")
    typealias Pause = (Duration) async -> Void

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
        init(_ board: NSPasteboard) {
            items = (board.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
            }
        }
        func restore(to board: NSPasteboard, ifUnchanged count: Int) {
            guard board.changeCount == count else { return }
            board.clearContents()
            board.writeObjects(items.map { data in
                let item = NSPasteboardItem()
                for (type, value) in data { item.setData(value, forType: type) }
                return item
            })
        }
    }

    static func readSelection(board: NSPasteboard = .general, isCurrent: () -> Bool,
                              sendCopy: () -> Bool = { postKey(8) },
                              pause: Pause = { try? await Task.sleep(for: $0) }) async -> String? {
        guard !leased, !Task.isCancelled, isCurrent() else { return nil }
        leased = true
        defer { leased = false }
        let saved = Snapshot(board)
        board.clearContents()
        board.setString(UUID().uuidString, forType: markerType)
        var ownedCount = board.changeCount
        defer { saved.restore(to: board, ifUnchanged: ownedCount) }
        guard sendCopy() else { return nil }
        for _ in 0..<20 {
            await pause(.milliseconds(40))
            if board.changeCount != ownedCount {
                // Copy has answered. A later clipboard generation belongs to the user.
                guard !Task.isCancelled, isCurrent() else { return nil }
                ownedCount = board.changeCount
                let copied = board.string(forType: .string)
                guard !Task.isCancelled, isCurrent(), let copied, !copied.isEmpty,
                      copied.utf8.count <= WritingAssistantService.maximumSourceLength else { return nil }
                return copied
            }
            guard !Task.isCancelled, isCurrent() else { return nil }
        }
        return nil
    }

    static func replaceSelection(_ original: String, with replacement: String,
                                 board: NSPasteboard = .general, isCurrent: () -> Bool,
                                 sendCopy: () -> Bool = { postKey(8) },
                                 sendPaste: () -> Bool = { postKey(9) },
                                 pause: Pause = { duration in
                                     await Task.detached { try? await Task.sleep(for: duration) }.value
                                 }) async -> Bool {
        guard let current = await readSelection(board: board, isCurrent: isCurrent, sendCopy: sendCopy, pause: pause),
              current == original else { return false }
        return await paste(replacement, board: board, isCurrent: isCurrent, sendPaste: sendPaste, pause: pause)
    }

    static func paste(_ text: String, board: NSPasteboard = .general, isCurrent: () -> Bool,
                      sendPaste: () -> Bool = { postKey(9) },
                      pause: Pause = { duration in
                          await Task.detached { try? await Task.sleep(for: duration) }.value
                      }) async -> Bool {
        guard !leased, !Task.isCancelled, isCurrent() else { return false }
        leased = true
        defer { leased = false }
        let saved = Snapshot(board)
        board.clearContents()
        board.setString(text, forType: .string)
        let ownedCount = board.changeCount
        defer { saved.restore(to: board, ifUnchanged: ownedCount) }
        await pause(.milliseconds(50))
        guard !Task.isCancelled, isCurrent(), board.changeCount == ownedCount, sendPaste() else { return false }
        // Do not retry a dispatched paste: opaque editors cannot prove it didn't land.
        await pause(.milliseconds(600))
        return true
    }

    private static func postKey(_ key: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// Any real typing or mouse selection in the destination invalidates an opaque
/// selection, even when the replacement text happens to equal the previous text.
@MainActor
final class WritingSelectionLease {
    private(set) var changed = false
    private var monitor: Any?
    init(pid: pid_t) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != WritingClipboard.eventTag else { return }
            Task { @MainActor in
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { self?.changed = true }
            }
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
