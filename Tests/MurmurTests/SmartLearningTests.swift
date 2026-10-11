import Foundation
import MurmurDictionary
import Testing
@testable import Murmur

@MainActor
struct SmartLearningTests {
    @Test func extractsNameAndIgnoresRepetition() {
        let edits = CorrectionDiff.changes(before: "Can you can you please ask Mosa to call?", after: "Can you please ask Mohsin to call?")
        #expect(edits.contains(CorrectionEdit(before: "Mosa", after: "Mohsin")))
        #expect(!edits.contains { $0.before.lowercased().contains("can you") })
        #expect(CorrectionDiff.changes(before: "hello", after: "hello there").isEmpty)
        #expect(CorrectionDiff.changes(before: "Hello!", after: "Hello.").isEmpty)
    }

    @Test func validatesModelDecisionsAgainstActualEdit() {
        let edit = CorrectionEdit(before: "Mosa", after: "Mohsin")
        let valid = #"{"reusable":true,"type":"proper_name","canonical":"Mohsin","aliases":["Mosa"],"confidence":0.98}"#
        #expect(CorrectionClassifier.decode(valid, edit: edit)?.canonical == "Mohsin")
        #expect(CorrectionClassifier.decode(valid.replacingOccurrences(of: "Mohsin", with: "Alice"), edit: edit) == nil)
        #expect(CorrectionClassifier.decode(valid.replacingOccurrences(of: "proper_name", with: "style_edit"), edit: edit) == nil)
        #expect(CorrectionClassifier.decode(valid.replacingOccurrences(of: "0.98", with: "1.2"), edit: edit) == nil)
        #expect(CorrectionClassifier.decode("not JSON", edit: edit) == nil)
    }

    @Test func storeMergesAliasesAndPreservesScopeAcrossReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("terms.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LearnedTermStore(fileURL: url)
        #expect(store.save(canonical: "Mohsin", aliases: ["Mosa"], bundleID: nil))
        #expect(store.save(canonical: "Mohsin", aliases: ["Mosen"], bundleID: nil))
        #expect(store.terms.count == 1)
        #expect(Set(store.terms[0].aliases) == Set(["Mosa", "Mosen"]))
        #expect(store.save(canonical: "Qwen", aliases: ["Quinn"], bundleID: "test.editor"))
        let loaded = LearnedTermStore(fileURL: url)
        #expect(loaded.entries(for: nil).allSatisfy { $0.write != "Qwen" })
        #expect(loaded.entries(for: "test.editor").contains { $0.write == "Qwen" })
        #expect(!loaded.save(canonical: "Someone else", aliases: ["Mosa"], bundleID: nil))
        #expect(!loaded.save(canonical: "Alice", aliases: ["Mohsin"], bundleID: nil))
        loaded.undo()
        #expect(loaded.terms.count == 2)
    }

    @Test func migratesWithoutDuplicateTermsOrSnippets() {
        let terms = LearnedTermStore.importTerms([
            .term("Mohsin"), .correction(hear: "Mosa", write: "Mohsin"),
            .correction(hear: "Mosen", write: "Mohsin"), .snippet(hear: "intro", write: "Hello")
        ])
        #expect(terms.count == 1)
        #expect(terms[0].aliases == ["Mosa", "Mosen"])
    }

    @Test func protectionDoesNotCascadeOrLoseNames() {
        let entries: [DictionaryEntry] = [.correction(hear: "Mosa", write: "Mohsin"), .correction(hear: "Mohsin", write: "Alice")]
        #expect(CanonicalProtection.protect(original: "Ask Mohsin.", candidate: "Ask mohsin.", entries: entries) == "Ask Mohsin.")
        #expect(CanonicalProtection.protect(original: "Ask Mohsin.", candidate: "Ask Alice.", entries: entries) == nil)
        #expect(CanonicalProtection.protect(original: "Ask Mohsin twice, Mohsin.", candidate: "Ask Mohsin twice.", entries: entries) == nil)
    }

    @Test func trackingRequiresExactInsertionAndUnchangedSurroundings() {
        let snapshot = InsertionSnapshot(before: "Dear:  Thanks", selection: NSRange(location: 6, length: 0), inserted: "Ask Mosa.")!
        #expect(snapshot.editedRegion(in: "Dear: Ask Mohsin. Thanks") == "Ask Mohsin.")
        #expect(snapshot.editedRegion(in: "Other: Ask Mohsin. Thanks") == nil)
        #expect(InsertionSnapshot(before: "Hi", selection: NSRange(location: 99, length: 0), inserted: "Ask Mosa.") == nil)
    }
}

@Suite("Learning model fixture export")
struct LearningModelFixtureTests {
    @Test func export() throws {
        guard let path = ProcessInfo.processInfo.environment["MURMUR_LEARNING_EXPORT"] else { return }
        let cases: [(String, String, String)] = [
            ("name", "Mosa", "Mohsin"), ("brand", "whisper flow", "Wispr Flow"),
            ("technical", "post grass sequel", "PostgreSQL"), ("style", "good", "performing extremely well"),
            ("content", "tomorrow", "Friday"), ("person_change", "Alice", "Bob"),
            ("repetition", "can you can you", "can you"), ("capitalization", "github", "GitHub")
        ]
        let requests: [[String: Any]] = try cases.map { id, before, after in
            ["id": id, "operation": "learning", "source": before,
             "system": CorrectionClassifier.prompt,
             "user": String(decoding: try JSONSerialization.data(withJSONObject: ["before": before, "after": after]), as: UTF8.self),
             "max_tokens": 180, "must_preserve": [], "must_not": []]
        }
        try JSONSerialization.data(withJSONObject: ["requests": requests], options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

@MainActor
struct LearnedTermPersistenceTests {
    @Test func corruptArchiveIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not a dictionary".utf8)
        try original.write(to: url)
        let store = LearnedTermStore(fileURL: url)
        #expect(store.isReadOnly)
        #expect(!store.save(canonical: "Mohsin", aliases: ["Mosa"], bundleID: nil))
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func failedSaveDoesNotPublishAndUndoRestoresAliases() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("terms.json")
        let store = LearnedTermStore(fileURL: file)
        #expect(store.save(canonical: "Mohsin", aliases: ["Mosa"], bundleID: nil))
        #expect(store.save(canonical: "Mohsin", aliases: ["Mosen"], bundleID: nil))
        store.undo()
        #expect(store.terms.first?.aliases == ["Mosa"])
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(!store.save(canonical: "Qwen", aliases: ["Quinn"], bundleID: nil))
        #expect(store.terms.count == 1)
    }
    @Test func thresholdsAndOffMode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LearnedTermStore(fileURL: url)
        let decision = LearnedDecision(reusable: true, type: "proper_name", canonical: "Mohsin", aliases: ["Mosa"], confidence: 0.98)
        store.receive(decision, bundleID: "test")
        #expect(store.terms.isEmpty)
        #expect(store.suggestions.count == 1)
        store.accept(store.suggestions[0])
        #expect(store.terms.count == 1)
        #expect(store.suggestions.isEmpty)
        store.undo()
        #expect(store.terms.isEmpty)
        #expect(store.suggestions.count == 1)
        store.setMode(.off)
        store.receive(decision, bundleID: nil)
        #expect(store.terms.isEmpty)
        store.setMode(.automatic)
        store.receive(decision, bundleID: "test")
        #expect(store.terms.count == 1)
    }
}
