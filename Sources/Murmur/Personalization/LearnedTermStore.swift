import Foundation
import MurmurDictionary
import Observation

enum SmartLearningMode: String, Codable, CaseIterable {
    case automatic = "Automatic", review = "Ask me first", off = "Off"
}

struct LearnedTerm: Identifiable, Codable, Equatable {
    var id = UUID()
    var canonical: String
    var aliases: [String]
    var bundleID: String?
    var source = "Manually added"
    var confidence = 1.0
    var isEnabled = true
    var updatedAt = Date()
    var timesCorrected = 1
}

@MainActor @Observable
final class LearnedTermStore {
    static let shared: LearnedTermStore = {
        let store = LearnedTermStore(fileURL: MurmurStorage.directory.appendingPathComponent("learned-terms.json"))
        store.importLegacy(DictionaryStore.shared.entries)
        return store
    }()
    private struct Archive: Codable, Equatable {
        var version = 1
        var mode: SmartLearningMode = .review
        var terms: [LearnedTerm] = []
        var suggestions: [LearnedTerm] = []
        var importedLegacy = false
        var migratedExamples: [UUID] = []
        var migrationPolicyVersion: Int?
    }
    private var archive = Archive()
    private var previous: Archive?
    let fileURL: URL
    private(set) var errorMessage: String?
    private(set) var changeID = UUID()
    private(set) var lastAction: String?
    private(set) var isReadOnly = false
    private(set) var isMigrating = false
    var terms: [LearnedTerm] { archive.terms }
    var suggestions: [LearnedTerm] { archive.suggestions }
    var mode: SmartLearningMode { archive.mode }
    var canUndo: Bool { previous != nil }

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let value = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard value.version == 1,
                  (value.terms + value.suggestions).allSatisfy({ Self.valid($0.canonical) && $0.aliases.allSatisfy(Self.valid) && $0.confidence.isFinite && (0...1).contains($0.confidence) }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            archive = value
        } catch {
            isReadOnly = true
            errorMessage = "Couldn’t read the learned dictionary. Your file is preserved. Restore a valid copy and restart Murmur."
        }
    }

    static func valid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 120
            && !text.contains(where: \.isNewline) && !text.hasPrefix("#") && !text.contains("->") && !text.contains("=>")
    }

    @discardableResult private func commit(_ next: Archive, action: String, undoable: Bool = true) -> Bool {
        guard !isReadOnly else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            if undoable { previous = archive }
            archive = next; changeID = UUID(); errorMessage = nil; lastAction = action
            return true
        } catch { errorMessage = "Couldn’t save the dictionary: \(error.localizedDescription)"; return false }
    }

    func setMode(_ mode: SmartLearningMode) {
        var next = archive; next.mode = mode
        if commit(next, action: "Smart Learning: \(mode.rawValue)") { CorrectionLearningMonitor.shared.cancel() }
    }
    func undo() {
        guard let previous else { return }
        if commit(previous, action: "Dictionary change undone", undoable: false) { self.previous = nil }
    }

    @discardableResult
    func save(id: UUID? = nil, canonical: String, aliases: [String], bundleID: String?, source: String = "Manually added", confidence: Double = 1) -> Bool {
        let canonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        var seen = Set<String>()
        let aliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
            .filter { !$0.isEmpty && $0 != canonical && seen.insert($0.lowercased()).inserted }
        guard Self.valid(canonical), aliases.allSatisfy(Self.valid), confidence.isFinite, (0...1).contains(confidence) else {
            errorMessage = "Use a word or short phrase, up to 120 characters."; return false
        }
        let existing = archive.terms.first { $0.id == id } ?? archive.terms.first { $0.canonical.caseInsensitiveCompare(canonical) == .orderedSame && $0.bundleID == bundleID }
        let combined = id == nil ? Array(Set((existing?.aliases ?? []) + aliases)).sorted() : aliases
        let conflict = archive.terms.contains { term in
            term.id != existing?.id && term.canonical != canonical
                && (term.bundleID == nil || bundleID == nil || term.bundleID == bundleID)
                && (term.aliases.contains { alias in combined.contains { $0.caseInsensitiveCompare(alias) == .orderedSame } }
                    || combined.contains { $0.caseInsensitiveCompare(term.canonical) == .orderedSame }
                    || term.aliases.contains { $0.caseInsensitiveCompare(canonical) == .orderedSame })
        }
        guard !conflict else { errorMessage = "This spelling overlaps another term or mishearing in this scope. Edit that term first to avoid conflicting replacements."; return false }
        var next = archive
        var term = existing ?? LearnedTerm(canonical: canonical, aliases: [], bundleID: bundleID)
        term.canonical = canonical; term.aliases = combined; term.bundleID = bundleID
        term.source = source; term.confidence = confidence; term.updatedAt = Date()
        if existing != nil { term.timesCorrected += 1 }
        next.terms.removeAll { $0.id == term.id }; next.terms.insert(term, at: 0)
        return commit(next, action: "Learned \(canonical)")
    }
    func toggle(_ term: LearnedTerm) {
        var next = archive
        guard let i = next.terms.firstIndex(where: { $0.id == term.id }) else { return }
        next.terms[i].isEnabled.toggle()
        _ = commit(next, action: next.terms[i].isEnabled ? "Term enabled" : "Term disabled")
    }
    func delete(_ term: LearnedTerm) {
        var next = archive; next.terms.removeAll { $0.id == term.id }
        _ = commit(next, action: "Term deleted")
    }
    func dismissSuggestion(_ term: LearnedTerm) {
        var next = archive; next.suggestions.removeAll { $0.id == term.id }
        _ = commit(next, action: "Suggestion dismissed")
    }
    func accept(_ term: LearnedTerm) {
        let before = archive
        if save(canonical: term.canonical, aliases: term.aliases, bundleID: term.bundleID, source: "Confirmed correction", confidence: term.confidence) {
            var next = archive; next.suggestions.removeAll { $0.id == term.id }
            if commit(next, action: "Learned \(term.canonical)", undoable: false) { previous = before }
        }
    }
    func receive(_ decision: LearnedDecision, bundleID: String?, forceReview: Bool = false) {
        guard mode != .off, !isReadOnly else { return }
        if !forceReview, mode == .automatic, decision.confidence >= 0.95,
           decision.aliases.allSatisfy({ DictionaryWarning.check(.correction(hear: $0, write: decision.canonical)).isEmpty }) {
            _ = save(canonical: decision.canonical, aliases: decision.aliases, bundleID: bundleID, source: "Learned automatically", confidence: decision.confidence)
        } else {
            guard !archive.suggestions.contains(where: { $0.canonical == decision.canonical && $0.aliases == decision.aliases && $0.bundleID == bundleID }),
                  !archive.terms.contains(where: { $0.canonical == decision.canonical && $0.bundleID == bundleID && Set(decision.aliases).isSubset(of: Set($0.aliases)) }) else { return }
            var next = archive
            next.suggestions.insert(LearnedTerm(canonical: decision.canonical, aliases: decision.aliases, bundleID: bundleID, source: "Suggested correction", confidence: decision.confidence), at: 0)
            next.suggestions = Array(next.suggestions.prefix(50))
            _ = commit(next, action: "Suggested \(decision.canonical)")
        }
    }

    func relevant(for bundleID: String?) -> [LearnedTerm] {
        terms.filter { $0.isEnabled && ($0.bundleID == nil || $0.bundleID == bundleID) }.sorted {
            if ($0.bundleID != nil) != ($1.bundleID != nil) { return $0.bundleID != nil }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.timesCorrected > $1.timesCorrected
        }
    }
    func entries(for bundleID: String?) -> [DictionaryEntry] {
        if isReadOnly { return DictionaryStore.shared.entries.filter { $0.kind != .snippet } }
        return relevant(for: bundleID).flatMap { term in
            [DictionaryEntry.term(term.canonical)] + term.aliases.map { .correction(hear: $0, write: term.canonical) }
        }
    }
    func vocabulary(for bundleID: String?) -> [String] {
        DictionaryCorrector.biasPhrases(from: entries(for: bundleID))
    }
    static func importTerms(_ entries: [DictionaryEntry]) -> [LearnedTerm] {
        var terms: [LearnedTerm] = []
        for entry in entries where entry.kind != .snippet && Self.valid(entry.write) && (entry.kind == .term || Self.valid(entry.hear)) {
            if let index = terms.firstIndex(where: { $0.canonical == entry.write && $0.isEnabled == entry.isEnabled }) {
                if entry.kind == .correction, !terms[index].aliases.contains(entry.hear) { terms[index].aliases.append(entry.hear) }
            } else {
                terms.append(LearnedTerm(canonical: entry.write, aliases: entry.kind == .correction ? [entry.hear] : [], bundleID: nil, source: "Imported dictionary", isEnabled: entry.isEnabled))
            }
        }
        return terms
    }
    private func importLegacy(_ entries: [DictionaryEntry]) {
        guard !archive.importedLegacy, !isReadOnly else { return }
        var next = archive; next.terms += Self.importTerms(entries); next.importedLegacy = true
        if !commit(next, action: "Dictionary imported; original file preserved", undoable: false) { isReadOnly = true }
    }
    @discardableResult
    func learn(before: String, after: String, bundleID: String?, forceReview: Bool = false) async -> Bool {
        guard mode != .off else { return false }
        for edit in CorrectionDiff.changes(before: before, after: after) {
            guard !Task.isCancelled, mode != .off else { return false }
            let decision: LearnedDecision?
            do { decision = try await CorrectionClassifier.classify(edit) }
            catch { return false }
            if let decision, !Task.isCancelled {
                let oldArchive = archive
                receive(decision, bundleID: bundleID, forceReview: forceReview)
                if !forceReview, archive != oldArchive, self === Self.shared, let lastAction {
                    LearningNotice.shared.show(lastAction, changeID: changeID)
                }
            }
        }
        return !Task.isCancelled
    }
    func migrateExamples(_ examples: [WritingExample], retry: Bool = false) async {
        guard mode != .off, WritingModelManager.shared.selectedModelURL != nil, !isReadOnly, !isMigrating else { return }
        isMigrating = true
        defer { isMigrating = false }
        if retry || archive.migrationPolicyVersion != 2 {
            var next = archive; next.migratedExamples = []; next.migrationPolicyVersion = 2
            guard commit(next, action: "Reviewing previous corrections", undoable: false) else { return }
        }
        for example in examples where !archive.migratedExamples.contains(example.id) {
            guard !Task.isCancelled, mode != .off else { return }
            // Old whole-sentence examples are ambiguous: review extracted names first.
            if example.isEnabled {
                guard await learn(before: example.raw, after: example.corrected, bundleID: example.bundleID, forceReview: true) else { return }
            }
            guard !Task.isCancelled, errorMessage == nil else { return }
            var next = archive; next.migratedExamples.append(example.id)
            let action = lastAction == "Reviewing previous corrections" ? "Previous corrections reviewed" : (lastAction ?? "Previous corrections reviewed")
            _ = commit(next, action: action, undoable: false)
        }
    }
}
