import Foundation
import Testing
@testable import Murmur

@Suite("Murmur storage migration")
struct MurmurStorageTests {
    @Test("Copies data into Murmur while preserving the previous files")
    func copiesData() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: base) }
        let previous = base.appendingPathComponent("previous")
        let current = base.appendingPathComponent("Murmur")
        try fileManager.createDirectory(at: previous.appendingPathComponent("WritingModels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: current.appendingPathComponent("WhisperModels"), withIntermediateDirectories: true)
        try Data("history".utf8).write(to: previous.appendingPathComponent("runs.jsonl"))
        try Data("model".utf8).write(to: previous.appendingPathComponent("WritingModels/model.gguf"))
        try Data("whisper".utf8).write(to: current.appendingPathComponent("WhisperModels/model"))

        try MurmurStorage.copyPreviousData(from: previous, to: current)

        #expect(try String(contentsOf: current.appendingPathComponent("runs.jsonl"), encoding: .utf8) == "history")
        #expect(try String(contentsOf: current.appendingPathComponent("WritingModels/model.gguf"), encoding: .utf8) == "model")
        #expect(try String(contentsOf: current.appendingPathComponent("WhisperModels/model"), encoding: .utf8) == "whisper")
        #expect(try String(contentsOf: previous.appendingPathComponent("runs.jsonl"), encoding: .utf8) == "history")
    }

    @Test("Existing Murmur data takes precedence and previous data remains recoverable")
    func preservesConflicts() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: base) }
        let previous = base.appendingPathComponent("previous")
        let current = base.appendingPathComponent("Murmur")
        try fileManager.createDirectory(at: previous, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: previous.appendingPathComponent("runs.jsonl"))
        try Data("new".utf8).write(to: current.appendingPathComponent("runs.jsonl"))

        try MurmurStorage.copyPreviousData(from: previous, to: current)

        #expect(try String(contentsOf: current.appendingPathComponent("runs.jsonl"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: previous.appendingPathComponent("runs.jsonl"), encoding: .utf8) == "old")
    }

    @Test("Preferences copy without overwriting current choices")
    func copiesPreferences() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let previousDomain = "previous.\(UUID().uuidString)"
        let currentDomain = "current.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: previousDomain)
            defaults.removePersistentDomain(forName: currentDomain)
        }
        defaults.setPersistentDomain(["shortcut": "left", "language": "ur"], forName: previousDomain)
        defaults.setPersistentDomain(["language": "en"], forName: currentDomain)

        MurmurStorage.copyPreviousPreferences(defaults: defaults, previousDomain: previousDomain, currentDomain: currentDomain)

        let current = defaults.persistentDomain(forName: currentDomain)
        #expect(current?["shortcut"] as? String == "left")
        #expect(current?["language"] as? String == "en")
        #expect(defaults.persistentDomain(forName: previousDomain)?["language"] as? String == "ur")
    }
}
