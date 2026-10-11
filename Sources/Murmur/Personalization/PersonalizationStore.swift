import Foundation
import Observation

/// Explicit writing preferences, isolated from the legacy dictionary and history.
/// Mutations publish only after an atomic save succeeds; corrupt/newer files are
/// preserved instead of silently replaced with defaults.
@MainActor
@Observable
final class PersonalizationStore {
    static let shared = PersonalizationStore()
    static let contextByteBudget = 6_000
    static let maximumMemoryLength = 2_000
    static let maximumExampleLength = 16_000

    private struct Archive: Codable, Equatable {
        var schemaVersion = 1
        var defaultStyleID = "clean"
        var memoryEnabled = true
        // Optional so existing version-one archives keep their previous setting.
        var correctionsEnabled: Bool? = nil
        var appRules: [WritingAppRule] = []
        var memories: [WritingMemory] = []
        var examples: [WritingExample] = []
    }

    private var archive = Archive()
    private var undoArchive: Archive?
    private(set) var lastAction: String?
    private(set) var errorMessage: String?
    private(set) var isReadOnly = false
    let fileURL: URL

    var defaultStyleID: String { archive.defaultStyleID }
    var memoryEnabled: Bool { archive.memoryEnabled }
    var correctionsEnabled: Bool { archive.correctionsEnabled ?? archive.memoryEnabled }
    var appRules: [WritingAppRule] { archive.appRules }
    var memories: [WritingMemory] { archive.memories }
    var examples: [WritingExample] { archive.examples }
    var canUndo: Bool { undoArchive != nil && !isReadOnly }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? MurmurStorage.directory
            .appendingPathComponent("writing-personalization.json")
        reload()
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            archive = Archive()
            isReadOnly = false
            errorMessage = nil
            undoArchive = nil
            lastAction = nil
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Archive.self, from: data)
            guard decoded.schemaVersion == 1 else {
                throw StoreError.message("These writing preferences use a newer format. Update Murmur before editing them. Your file has been kept unchanged.")
            }
            guard Self.isValid(decoded) else {
                throw StoreError.message("Some saved writing preferences are invalid. Your file has been kept unchanged. Restore a valid copy, then choose Reload.")
            }
            archive = decoded
            isReadOnly = false
            errorMessage = nil
            undoArchive = nil
            lastAction = nil
        } catch {
            isReadOnly = true
            errorMessage = (error as? StoreError)?.localizedDescription
                ?? "Murmur couldn't read your writing preferences. Your file has been kept unchanged. Restore a valid copy, then choose Reload."
        }
    }

    /// App-specific context takes priority; global notes follow. Correction examples
    /// are matched to the active style, so a casual edit cannot teach professional output.
    func context(for bundleID: String?, styleID: String? = nil) -> WritingContext {
        let selectedID = styleID ?? archive.appRules.first { $0.bundleID == bundleID }?.styleID
            ?? archive.defaultStyleID
        let style = WritingStyle.find(selectedID) ?? WritingStyle.builtIns[1]
        guard !isReadOnly else {
            return WritingContext(styleID: style.id, styleName: style.name,
                                  instruction: style.instruction, memory: "", examples: [])
        }

        let matchingMemories = archive.memories.filter {
            archive.memoryEnabled && $0.isEnabled && ($0.bundleID == nil || $0.bundleID == bundleID)
        }.sorted { left, right in
            if (left.bundleID != nil) != (right.bundleID != nil) { return left.bundleID != nil }
            return left.createdAt > right.createdAt
        }
        // Complete notes/examples only: clipping a saved instruction can invert it.
        var remaining = Self.contextByteBudget - style.instruction.utf8.count
        var memoryBudget = min(2_800, remaining)
        var notes: [String] = []
        for note in matchingMemories {
            let cost = note.text.utf8.count + (notes.isEmpty ? 0 : 2)
            guard cost <= memoryBudget else { continue }
            notes.append(note.text)
            memoryBudget -= cost
            remaining -= cost
        }
        let candidates = archive.examples.filter {
            correctionsEnabled && $0.isEnabled && $0.styleID == style.id
                && ($0.bundleID == nil || $0.bundleID == bundleID)
        }.sorted { left, right in
            if (left.bundleID != nil) != (right.bundleID != nil) { return left.bundleID != nil }
            return left.createdAt > right.createdAt
        }
        var selectedExamples: [WritingExample] = []
        for example in candidates {
            let cost = example.raw.utf8.count + example.corrected.utf8.count
            guard cost <= remaining, selectedExamples.count < 4 else { continue }
            selectedExamples.append(example)
            remaining -= cost
        }
        return WritingContext(styleID: style.id, styleName: style.name,
                              instruction: style.instruction, memory: notes.joined(separator: "\n\n"),
                              examples: selectedExamples)
    }

    @discardableResult
    func setDefaultStyle(_ styleID: String) -> Bool {
        guard WritingStyle.find(styleID) != nil else { return reject("Choose one of Murmur's writing styles.") }
        var next = archive
        next.defaultStyleID = styleID
        return commit(next, action: "Default style saved")
    }

    @discardableResult
    func setAppRule(bundleID: String, appName: String, styleID: String) -> Bool {
        guard Self.validBundleID(bundleID), WritingStyle.find(styleID) != nil else {
            return reject("Choose an app and a supported writing style.")
        }
        var next = archive
        next.appRules.removeAll { $0.bundleID == bundleID }
        next.appRules.append(WritingAppRule(bundleID: bundleID,
                                           appName: Self.cleanName(appName), styleID: styleID))
        next.appRules.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        return commit(next, action: "App style saved")
    }

    @discardableResult
    func deleteAppRule(bundleID: String) -> Bool {
        var next = archive
        next.appRules.removeAll { $0.bundleID == bundleID }
        return commit(next, action: "App style removed")
    }

    @discardableResult
    func setMemoryEnabled(_ enabled: Bool) -> Bool {
        var next = archive
        next.memoryEnabled = enabled
        return commit(next, action: enabled ? "Memory enabled" : "Memory paused")
    }

    @discardableResult
    func setCorrectionsEnabled(_ enabled: Bool) -> Bool {
        var next = archive
        next.correctionsEnabled = enabled
        return commit(next, action: enabled ? "Corrections enabled" : "Corrections paused")
    }

    @discardableResult
    func saveMemory(id: UUID? = nil, text: String, bundleID: String?, appName: String?, quietly: Bool = false) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumMemoryLength else {
            return reject("Write a memory between 1 and \(Self.maximumMemoryLength) characters.")
        }
        guard bundleID.map(Self.validBundleID) ?? true else { return reject("Choose an app for this memory.") }
        var next = archive
        if let id, let index = next.memories.firstIndex(where: { $0.id == id }) {
            next.memories[index].text = trimmed
            next.memories[index].bundleID = bundleID
            next.memories[index].appName = bundleID == nil ? nil : Self.cleanName(appName ?? "Selected app")
        } else {
            guard next.memories.count < 200 else { return reject("You have 200 memories. Remove one before adding another.") }
            next.memories.insert(WritingMemory(text: trimmed, bundleID: bundleID,
                appName: bundleID == nil ? nil : Self.cleanName(appName ?? "Selected app")), at: 0)
        }
        return commit(next, action: id == nil ? "Memory saved" : "Memory updated", quiet: quietly)
    }

    @discardableResult
    func deleteMemory(_ id: UUID, quietly: Bool = false) -> Bool {
        var next = archive
        next.memories.removeAll { $0.id == id }
        return commit(next, action: "Memory deleted", quiet: quietly)
    }

    @discardableResult
    func setMemoryEnabled(_ id: UUID, enabled: Bool) -> Bool {
        var next = archive
        guard let index = next.memories.firstIndex(where: { $0.id == id }) else { return false }
        next.memories[index].isEnabled = enabled
        return commit(next, action: enabled ? "Memory enabled" : "Memory disabled")
    }

    /// Editing a transcript does not imply consent to remember it. Only explicit
    /// opt-in creates an example; spelling aliases are never inferred here.
    @discardableResult
    func saveCorrection(raw: String, corrected: String, bundleID: String?, styleID: String, remember: Bool) -> Bool {
        guard remember else { return true }
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !corrected.isEmpty, raw != corrected else {
            return reject("Change the transcript before remembering a correction.")
        }
        guard raw.count <= Self.maximumExampleLength, corrected.count <= Self.maximumExampleLength else {
            return reject("This correction is too long to remember. Save a shorter example of the change.")
        }
        guard WritingStyle.find(styleID) != nil, bundleID.map(Self.validBundleID) ?? true else {
            return reject("Choose an app scope and a supported style for the correction.")
        }
        var next = archive
        if let index = next.examples.firstIndex(where: {
            $0.raw == raw && $0.corrected == corrected && $0.bundleID == bundleID && $0.styleID == styleID
        }) {
            next.examples[index].isEnabled = true
            next.examples[index].createdAt = Date()
        } else {
            guard next.examples.count < 500 else { return reject("You have 500 remembered corrections. Remove one before adding another.") }
            next.examples.insert(WritingExample(raw: raw, corrected: corrected, bundleID: bundleID,
                appName: bundleID.map { PersonalizationApplications.name(for: $0) }, styleID: styleID), at: 0)
        }
        return commit(next, action: "Correction remembered")
    }

    @discardableResult
    func deleteExample(_ id: UUID) -> Bool {
        var next = archive
        next.examples.removeAll { $0.id == id }
        return commit(next, action: "Correction forgotten")
    }

    @discardableResult
    func setExampleEnabled(_ id: UUID, enabled: Bool) -> Bool {
        var next = archive
        guard let index = next.examples.firstIndex(where: { $0.id == id }) else { return false }
        next.examples[index].isEnabled = enabled
        return commit(next, action: enabled ? "Correction enabled" : "Correction disabled")
    }

    @discardableResult
    func undoLastChange() -> Bool {
        guard let previous = undoArchive else { return false }
        guard commit(previous, action: "Change undone", keepUndo: false) else { return false }
        undoArchive = nil
        return true
    }

    private func commit(_ next: Archive, action: String, keepUndo: Bool = true, quiet: Bool = false) -> Bool {
        guard !isReadOnly else { return false }
        guard next != archive else { return true }
        guard Self.isValid(next) else { return reject("These writing preferences couldn't be saved. Check the selected app and text length.") }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            if quiet { undoArchive = nil }
            else if keepUndo { undoArchive = archive }
            archive = next
            lastAction = quiet ? nil : action
            errorMessage = nil
            return true
        } catch {
            return reject("Murmur couldn't save your writing preferences. Check available disk space and access to Application Support, then try again. Your previous preferences are still active.")
        }
    }

    private func reject(_ message: String) -> Bool {
        errorMessage = message
        return false
    }

    private static func validBundleID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 255 && !id.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    private static func cleanName(_ name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Selected app" : String(cleaned.prefix(120))
    }

    private static func isValid(_ value: Archive) -> Bool {
        value.schemaVersion == 1 && WritingStyle.find(value.defaultStyleID) != nil
            && Set(value.appRules.map(\.bundleID)).count == value.appRules.count
            && Set(value.memories.map(\.id)).count == value.memories.count
            && Set(value.examples.map(\.id)).count == value.examples.count
            && value.appRules.count <= 200 && value.memories.count <= 200 && value.examples.count <= 500
            && value.appRules.allSatisfy { validBundleID($0.bundleID) && WritingStyle.find($0.styleID) != nil }
            && value.memories.allSatisfy {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.text.count <= maximumMemoryLength && ($0.bundleID.map(validBundleID) ?? true)
            }
            && value.examples.allSatisfy {
                !$0.raw.isEmpty && !$0.corrected.isEmpty
                    && $0.raw.count <= maximumExampleLength && $0.corrected.count <= maximumExampleLength
                    && WritingStyle.find($0.styleID) != nil && ($0.bundleID.map(validBundleID) ?? true)
            }
    }

    private enum StoreError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }
}
