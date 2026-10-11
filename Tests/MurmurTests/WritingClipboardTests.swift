import AppKit
import Testing
@testable import Murmur

@Suite("Automatic editor selection", .serialized)
@MainActor
struct WritingClipboardTests {
    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: .init("murmur-test-\(UUID().uuidString)"))
        board.setString("existing clipboard", forType: .string)
        return board
    }

    @Test("Copy captures current selection and restores rich clipboard contents")
    func capture() async {
        let board = board()
        defer { board.releaseGlobally() }
        let rich = Data("<b>saved</b>".utf8)
        board.setData(rich, forType: .html)
        var commands = 0
        let text = await WritingClipboard.readSelection(board: board, isCurrent: { true }, sendCopy: {
            commands += 1
            board.clearContents(); board.setString("selected 👋 text", forType: .string)
            return true
        }, pause: { _ in })
        #expect(text == "selected 👋 text")
        #expect(commands == 1)
        #expect(board.string(forType: .string) == "existing clipboard")
        #expect(board.data(forType: .html) == rich)
    }

    @Test("Missing Copy response never edits unrelated old clipboard text")
    func missingCopy() async {
        let board = board()
        defer { board.releaseGlobally() }
        let text = await WritingClipboard.readSelection(board: board, isCurrent: { true }, sendCopy: { true }, pause: { _ in })
        #expect(text == nil)
        #expect(board.string(forType: .string) == "existing clipboard")
    }

    @Test("An opaque editor receives exactly one paste after selection revalidation")
    func replacement() async {
        let board = board()
        defer { board.releaseGlobally() }
        var pasted: [String] = []
        let success = await WritingClipboard.replaceSelection("draft", with: "Rewritten draft.", board: board,
            isCurrent: { true }, sendCopy: {
                board.clearContents(); board.setString("draft", forType: .string); return true
            }, sendPaste: {
                pasted.append(board.string(forType: .string) ?? ""); return true
            }, pause: { _ in })
        #expect(success)
        #expect(pasted == ["Rewritten draft."])
        #expect(board.string(forType: .string) == "existing clipboard")
    }

    @Test("Changing the selected text blocks delivery")
    func staleSelection() async {
        let board = board()
        defer { board.releaseGlobally() }
        var pasted = false
        let success = await WritingClipboard.replaceSelection("draft", with: "Rewritten draft.", board: board,
            isCurrent: { true }, sendCopy: {
                board.clearContents(); board.setString("new selection", forType: .string); return true
            }, sendPaste: { pasted = true; return true }, pause: { _ in })
        #expect(!success)
        #expect(!pasted)
    }

    @Test("Changing focus during copy preserves a newer user clipboard")
    func changedFocus() async {
        let board = board()
        defer { board.releaseGlobally() }
        var current = true
        let text = await WritingClipboard.readSelection(board: board, isCurrent: { current }, sendCopy: {
            current = false
            board.clearContents(); board.setString("user's new copy", forType: .string); return true
        }, pause: { _ in })
        #expect(text == nil)
        #expect(board.string(forType: .string) == "user's new copy")
    }

    @Test("Focus changes before paste prevent writing into another field")
    func changedBeforePaste() async {
        let board = board()
        defer { board.releaseGlobally() }
        var current = true, pasted = false
        let sent = await WritingClipboard.paste("result", board: board, isCurrent: { current },
            sendPaste: { pasted = true; return true }, pause: { _ in current = false })
        #expect(!sent)
        #expect(!pasted)
        #expect(board.string(forType: .string) == "existing clipboard")
    }

    @Test("User clipboard updates after paste are not overwritten")
    func newerClipboard() async {
        let board = board()
        defer { board.releaseGlobally() }
        let sent = await WritingClipboard.paste("result", board: board, isCurrent: { true }, sendPaste: {
            board.clearContents(); board.setString("new user copy", forType: .string); return true
        }, pause: { _ in })
        #expect(sent)
        #expect(board.string(forType: .string) == "new user copy")
    }
}
