import Foundation
import Testing
@testable import Murmur

@Suite("Explicit writing personalization")
struct PersonalizationStoreTests {
    @Test("reading default preferences does not create files")
    @MainActor
    func defaultsDoNotWrite() throws {
        try withTemporaryStore { store, url in
            #expect(store.defaultStyleID == "clean")
            #expect(store.context(for: nil).styleName == "Clean")
            #expect(store.context(for: nil).examples.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("app rules override the default and persist without touching other apps")
    @MainActor
    func styleSelection() throws {
        try withTemporaryStore { store, url in
            #expect(store.setDefaultStyle("faithful"))
            #expect(store.setAppRule(bundleID: "test.mail", appName: "Mail", styleID: "professional"))
            #expect(store.setAppRule(bundleID: "test.chat", appName: "Messages", styleID: "casual"))
            let reopened = PersonalizationStore(fileURL: url)
            #expect(reopened.context(for: "test.mail").styleID == "professional")
            #expect(reopened.context(for: "test.chat").styleID == "casual")
            #expect(reopened.context(for: "test.editor").styleID == "faithful")
            #expect(reopened.context(for: nil).styleID == "faithful")
            #expect(reopened.deleteAppRule(bundleID: "test.mail"))
            #expect(reopened.context(for: "test.mail").styleID == "faithful")
            #expect(reopened.undoLastChange())
            #expect(reopened.context(for: "test.mail").styleID == "professional")
        }
    }

    @Test("memories never cross app scope and disabling memory removes prompt context")
    @MainActor
    func memoryScope() throws {
        try withTemporaryStore { store, _ in
            #expect(store.saveMemory(text: "Use British spelling.", bundleID: nil, appName: nil))
            #expect(store.saveMemory(text: "My project is called Lighthouse.", bundleID: "test.mail", appName: "Mail"))
            #expect(store.saveMemory(text: "This is a private chat preference.", bundleID: "test.chat", appName: "Messages"))
            let mail = store.context(for: "test.mail")
            #expect(mail.memory.contains("Lighthouse"))
            #expect(mail.memory.contains("British"))
            #expect(!mail.memory.contains("private chat"))
            #expect(!store.context(for: nil).memory.contains("Lighthouse"))
            #expect(store.saveCorrection(raw: "original", corrected: "corrected", bundleID: nil, styleID: "clean", remember: true))
            #expect(store.setMemoryEnabled(false))
            #expect(store.context(for: "test.mail").memory.isEmpty)
            #expect(store.context(for: "test.mail").examples.isEmpty)
            #expect(store.memories.count == 3)
            #expect(store.examples.count == 1)
            #expect(store.setMemoryEnabled(true))
            #expect(!store.context(for: "test.mail").memory.isEmpty)
        }
    }

    @Test("memory and saved corrections can be used independently")
    @MainActor
    func independentContextControls() throws {
        try withTemporaryStore { store, url in
            #expect(store.saveMemory(text: "Use British spelling.", bundleID: nil, appName: nil))
            #expect(store.saveCorrection(raw: "rough draft", corrected: "final draft", bundleID: nil, styleID: "clean", remember: true))
            #expect(store.setCorrectionsEnabled(false))
            #expect(!store.context(for: nil).memory.isEmpty)
            #expect(store.context(for: nil).examples.isEmpty)
            #expect(store.setMemoryEnabled(false))
            #expect(store.setCorrectionsEnabled(true))
            #expect(store.context(for: nil).memory.isEmpty)
            #expect(store.context(for: nil).examples.count == 1)
            let reopened = PersonalizationStore(fileURL: url)
            #expect(!reopened.memoryEnabled)
            #expect(reopened.correctionsEnabled)
            #expect(reopened.context(for: nil).examples.count == 1)
        }
    }

    @Test("a transcript edit without remember consent creates no learning data")
    @MainActor
    func rememberConsent() throws {
        try withTemporaryStore { store, url in
            #expect(store.saveCorrection(raw: "raw words", corrected: "correct words", bundleID: "test.mail", styleID: "professional", remember: false))
            #expect(store.examples.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(store.saveCorrection(raw: "raw words", corrected: "correct words", bundleID: "test.mail", styleID: "professional", remember: true))
            #expect(store.examples.count == 1)
            #expect(store.saveCorrection(raw: "raw words", corrected: "correct words", bundleID: "test.mail", styleID: "professional", remember: true))
            #expect(store.examples.count == 1)
            #expect(store.context(for: "test.mail").examples.isEmpty) // Default is Clean.
            #expect(store.setAppRule(bundleID: "test.mail", appName: "Mail", styleID: "professional"))
            #expect(store.context(for: "test.mail").examples.count == 1)
            #expect(store.context(for: "test.chat").examples.isEmpty)
            let reopened = PersonalizationStore(fileURL: url)
            #expect(reopened.examples.first?.raw == "raw words")
            #expect(reopened.examples.first?.corrected == "correct words")
        }
    }

    @Test("global corrections still require the matching writing style")
    @MainActor
    func exampleStyles() throws {
        try withTemporaryStore { store, _ in
            #expect(store.saveCorrection(raw: "please", corrected: "kindly", bundleID: nil, styleID: "professional", remember: true))
            #expect(store.context(for: nil).examples.isEmpty)
            #expect(store.setDefaultStyle("professional"))
            #expect(store.context(for: "test.editor").examples.count == 1)
            let id = try #require(store.examples.first?.id)
            #expect(store.setExampleEnabled(id, enabled: false))
            #expect(store.context(for: "test.editor").examples.isEmpty)
            #expect(store.examples.count == 1)
        }
    }

    @Test("prompt size is bounded in UTF-8 bytes and complete examples are never truncated")
    @MainActor
    func contextBudget() throws {
        try withTemporaryStore { store, _ in
            for index in 0..<12 {
                #expect(store.saveMemory(text: "Preference \(index): " + String(repeating: "語", count: 250), bundleID: nil, appName: nil))
            }
            for index in 0..<12 {
                #expect(store.saveCorrection(raw: "Original \(index) " + String(repeating: "é", count: 180),
                    corrected: "Correction \(index) " + String(repeating: "é", count: 180),
                    bundleID: nil, styleID: "clean", remember: true))
            }
            #expect(store.saveCorrection(raw: String(repeating: "a", count: 8_000),
                corrected: String(repeating: "b", count: 8_000), bundleID: nil, styleID: "clean", remember: true))
            let context = store.context(for: nil)
            #expect(context.utf8ByteCount <= PersonalizationStore.contextByteBudget)
            #expect(context.examples.count <= 4)
            #expect(!context.examples.isEmpty)
            #expect(context.examples.allSatisfy { selected in
                store.examples.contains { $0.raw == selected.raw && $0.corrected == selected.corrected }
            })
            #expect(!context.examples.contains { $0.raw.count == 8_000 })
            #expect(store.examples.count == 13) // Context selection never discards saved data.
        }
    }

    @Test("delete and undo restore persisted memories and examples")
    @MainActor
    func undoPersists() throws {
        try withTemporaryStore { store, url in
            #expect(store.saveMemory(text: "Prefer short paragraphs.", bundleID: nil, appName: nil))
            let note = try #require(store.memories.first)
            #expect(store.deleteMemory(note.id))
            #expect(PersonalizationStore(fileURL: url).memories.isEmpty)
            #expect(store.undoLastChange())
            #expect(PersonalizationStore(fileURL: url).memories.first == note)
            #expect(!store.canUndo)
            #expect(store.saveCorrection(raw: "a raw phrase", corrected: "a corrected phrase", bundleID: nil, styleID: "clean", remember: true))
            let example = try #require(store.examples.first)
            #expect(store.deleteExample(example.id))
            #expect(store.undoLastChange())
            #expect(PersonalizationStore(fileURL: url).examples.first == example)
        }
    }

    @Test("invalid user input never replaces a working preference")
    @MainActor
    func validation() throws {
        try withTemporaryStore { store, _ in
            #expect(!store.setDefaultStyle("unknown"))
            #expect(store.defaultStyleID == "clean")
            #expect(!store.setAppRule(bundleID: "", appName: "", styleID: "clean"))
            #expect(!store.saveMemory(text: " \n ", bundleID: nil, appName: nil))
            #expect(!store.saveCorrection(raw: "same", corrected: "same", bundleID: nil, styleID: "clean", remember: true))
            #expect(store.examples.isEmpty)
            #expect(store.errorMessage != nil)
        }
    }

    @Test("corrupt preferences are preserved and cannot be overwritten by a mutation")
    @MainActor
    func corruptFilePreserved() throws {
        try withTemporaryStore { store, url in
            #expect(store.setDefaultStyle("professional"))
            let damaged = Data("{ incomplete file".utf8)
            try damaged.write(to: url)
            let reopened = PersonalizationStore(fileURL: url)
            #expect(reopened.isReadOnly)
            #expect(reopened.errorMessage != nil)
            #expect(!reopened.setDefaultStyle("casual"))
            #expect(try Data(contentsOf: url) == damaged)
        }
    }

    @Test("future schema remains readable only by a compatible app")
    @MainActor
    func futureSchemaPreserved() throws {
        try withTemporaryStore { store, url in
            #expect(store.setDefaultStyle("professional"))
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            object["schemaVersion"] = 2
            let future = try JSONSerialization.data(withJSONObject: object)
            try future.write(to: url)
            let reopened = PersonalizationStore(fileURL: url)
            #expect(reopened.isReadOnly)
            #expect(!reopened.saveMemory(text: "Do not overwrite.", bundleID: nil, appName: nil))
            #expect(try Data(contentsOf: url) == future)
        }
    }

    @Test("failed disk save does not publish unsaved state")
    @MainActor
    func failedSave() throws {
        try withTemporaryStore { _, url in
            let blocker = url.deletingLastPathComponent().appendingPathComponent("not-a-directory")
            try Data("file".utf8).write(to: blocker)
            let store = PersonalizationStore(fileURL: blocker.appendingPathComponent("preferences.json"))
            #expect(!store.setDefaultStyle("professional"))
            #expect(store.defaultStyleID == "clean")
            #expect(!store.canUndo)
            #expect(store.errorMessage != nil)
        }
    }

    @MainActor
    private func withTemporaryStore(_ body: (PersonalizationStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-writing-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("writing-personalization.json")
        try body(PersonalizationStore(fileURL: url), url)
    }
}
