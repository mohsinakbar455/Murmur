import MurmurDictionary
import Foundation
import CryptoKit

/// One completed dictation.
struct DictationRun: Codable, Sendable, Identifiable {
    /// Stable identity, so a single run can be deleted without matching on its text.
    ///
    /// Decoded leniently: runs written before this existed have no `id` field, and failing
    /// their whole line would throw away the user's history to add a delete button. Those
    /// receive deterministic IDs on load and persist them on the next rewrite.
    var id: UUID = UUID()

    let date: Date
    let engine: String
    /// How long the key was held.
    let audioSeconds: Double
    /// Release → final text ready. This is the latency you actually feel.
    let processSeconds: Double
    var text: String
    /// Dictionary corrections that fired on this transcript. Recorded so history can show
    /// whether the dictionary is actually doing anything, rather than leaving it to faith.
    ///
    /// Optional for backwards compatibility: runs recorded before the dictionary existed
    /// decode with this nil rather than failing the whole line.
    var corrections: [AppliedCorrection]?
    var rawText: String?
    var deliveredText: String?
    var bundleID: String?
    var styleID: String?
    var cleanupEngine: String?
    var cleanupSeconds: Double?
    var fallbackReason: String?

    var realtimeFactor: Double { audioSeconds / max(processSeconds, 0.0001) }
    var characters: Int { text.count }

    init(
        id: UUID = UUID(),
        date: Date,
        engine: String,
        audioSeconds: Double,
        processSeconds: Double,
        text: String,
        corrections: [AppliedCorrection]? = nil,
        rawText: String? = nil, bundleID: String? = nil, styleID: String? = nil,
        cleanupEngine: String? = nil, cleanupSeconds: Double? = nil, fallbackReason: String? = nil
    ) {
        self.id = id
        self.date = date
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.text = text
        self.corrections = corrections
        self.rawText = rawText
        self.bundleID = bundleID
        self.styleID = styleID
        self.cleanupEngine = cleanupEngine
        self.cleanupSeconds = cleanupSeconds
        self.fallbackReason = fallbackReason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        engine = try container.decode(String.self, forKey: .engine)
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        processSeconds = try container.decode(Double.self, forKey: .processSeconds)
        text = try container.decode(String.self, forKey: .text)
        corrections = try container.decodeIfPresent([AppliedCorrection].self, forKey: .corrections)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        deliveredText = try container.decodeIfPresent(String.self, forKey: .deliveredText)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        styleID = try container.decodeIfPresent(String.self, forKey: .styleID)
        cleanupEngine = try container.decodeIfPresent(String.self, forKey: .cleanupEngine)
        cleanupSeconds = try container.decodeIfPresent(Double.self, forKey: .cleanupSeconds)
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
    }
}

/// Persists dictations for the native Murmur dashboard.
@MainActor
enum RunLog {
    static var directory: URL {
        let base = MurmurStorage.directory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var runsURL: URL { directory.appendingPathComponent("runs.jsonl") }

    static func record(_ run: DictationRun) {
        guard Settings.shared.saveHistory else { return }
        append(run)
        RunStore.shared.reload()
    }

    private static func append(_ run: DictationRun) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(run) else { return }
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: runsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: runsURL)
        }
    }

    static func load() -> [DictationRun] {
        guard let data = try? Data(contentsOf: runsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).enumerated().compactMap { index, line in
            let bytes = Data(line)
            guard var run = try? decoder.decode(DictationRun.self, from: bytes) else { return nil }
            if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], object["id"] == nil {
                var seed = bytes
                seed.append(contentsOf: String(index).utf8)
                let hash = Array(SHA256.hash(data: seed).prefix(16))
                run.id = UUID(uuid: (hash[0],hash[1],hash[2],hash[3],hash[4],hash[5],hash[6],hash[7],hash[8],hash[9],hash[10],hash[11],hash[12],hash[13],hash[14],hash[15]))
            }
            return run
        }
    }

    @discardableResult
    static func correct(id: UUID, text: String) -> Bool {
        var runs = load()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let index = runs.firstIndex(where: { $0.id == id }) else { return false }
        if runs[index].deliveredText == nil { runs[index].deliveredText = runs[index].text }
        runs[index].text = text
        return rewrite(runs)
    }

    /// Deletes one run.
    static func delete(_ run: DictationRun) {
        delete(ids: [run.id])
    }

    static func delete(ids: Set<UUID>) {
        rewrite(load().filter { !ids.contains($0.id) })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: runsURL)
        RunStore.shared.reload()
    }

    /// Replaces the whole file. Deleting can't be an append, and rewriting also persists the
    /// ids that older runs were assigned on load.
    @discardableResult
    private static func rewrite(_ runs: [DictationRun]) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = runs.compactMap { run -> String? in
            guard let data = try? encoder.encode(run) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        // Atomic: a partial write here would lose history that the user didn't ask to delete.
        do {
            try (body.isEmpty ? "" : body + "\n").write(to: runsURL, atomically: true, encoding: .utf8)
            RunStore.shared.reload()
            return true
        } catch { return false }
    }
}
