import Foundation
import MurmurDictionary
import Observation

/// User-owned filler-word preferences and the deterministic filter built from them.
@MainActor
@Observable
final class FillerWordStore {
    static let defaultWords = ["um", "uh", "erm", "uhm", "umm", "uhh", "hmm", "mhm"]
    static let shared = FillerWordStore()

    private(set) var isEnabled: Bool
    private(set) var words: [String]

    private let fileURL: URL

    static var defaultFileURL: URL {
        let base = MurmurStorage.directory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("filler-words.json")
    }

    init(fileURL: URL = FillerWordStore.defaultFileURL) {
        self.fileURL = fileURL

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            isEnabled = saved.isEnabled
            words = Self.normalizedUnique(saved.words)
        } else {
            isEnabled = true
            words = Self.defaultWords
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        save()
    }

    /// Adds a normalized entry. Returns false for a blank or duplicate value.
    @discardableResult
    func add(_ candidate: String) -> Bool {
        guard let normalized = FillerWordFilter.normalize(candidate),
              !words.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame })
        else { return false }

        words.append(normalized)
        save()
        return true
    }

    func delete(_ word: String) {
        let originalCount = words.count
        words.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        if words.count != originalCount { save() }
    }

    func resetToDefaults() {
        words = Self.defaultWords
        save()
    }

    func filtered(by query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return words }
        return words.filter { $0.localizedStandardContains(trimmed) }
    }

    func apply(to text: String) -> FillerWordFilter.Result {
        guard isEnabled else {
            return FillerWordFilter.Result(text: text, removalCount: 0)
        }
        return FillerWordFilter(words: words).apply(to: text)
    }

    private func save() {
        let snapshot = Snapshot(schemaVersion: 1, isEnabled: isEnabled, words: words)
        guard let data = try? JSONEncoder.pretty.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func normalizedUnique(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap(FillerWordFilter.normalize).filter {
            seen.insert($0).inserted
        }
    }

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let isEnabled: Bool
        let words: [String]
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
