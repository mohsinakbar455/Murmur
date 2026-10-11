import Foundation
import Testing
@testable import Murmur

/// Opt-in export of the actual app prompts, using synthetic inputs only.
/// Ordinary tests do not start a model or read the user's personalization.
@Suite("Writing policy benchmark export")
struct WritingPolicyBenchmarkTests {
    @Test @MainActor
    func checkModelResults() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let resultsPath = environment["MURMUR_WRITING_BENCHMARK_RESULTS"],
              let corpusPath = environment["MURMUR_WRITING_BENCHMARK_CORPUS"] else { return }
        let corpus = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: corpusPath))) as? [String: Any])
        let cases = try #require(corpus["cases"] as? [[String: Any]])
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: resultsPath))) as? [String: Any])
        let rows = try #require(report["results"] as? [[String: Any]])
        var checked: [[String: Any]] = []
        for row in rows {
            let id = try #require(row["id"] as? String)
            let item = try #require(cases.first { $0["id"] as? String == id })
            let source = try #require(item["source"] as? String)
            let output = try #require(row["output"] as? String)
            let operation = try #require(row["operation"] as? String)
            let baseline = row["variant"] as? String == "baseline"
            let started = ContinuousClock.now
            let accepted: Bool
            if operation.hasPrefix("dictation_") {
                accepted = baseline ? Self.baselineAccepts(source, output)
                    : TranscriptOutputCheck.accepts(original: source, candidate: DictationIntent.lists(output),
                        styleID: String(operation.dropFirst("dictation_".count)))
            } else {
                let action = try #require(WritingAction(rawValue: operation))
                let structural = (try? WritingAssistantService.checkedOutput(output)) != nil
                accepted = structural && (baseline || WritingOutputCheck.assistantConcern(action: action, source: source, candidate: output) == nil)
            }
            if !baseline {
                if let expectedEmoji = item["expected_emoji"] as? [String] {
                    #expect(DictationIntent.emojiCharacters(output) == expectedEmoji, "Emoji request failed: \(id)")
                    #expect(accepted, "Output rejected: \(id)")
                }
                for literal in item["required_text"] as? [String] ?? [] {
                    #expect(output.localizedCaseInsensitiveContains(literal), "Missing requested words: \(id)")
                }
            }
            let duration = started.duration(to: .now).components
            var result = row
            result["check_microseconds"] = Double(duration.seconds) * 1e6 + Double(duration.attoseconds) / 1e12
            result["output_check_accepted"] = accepted && row["finish_reason"] as? String == "stop"
            if operation.hasPrefix("dictation_") {
                result["within_warm_cleanup_budget"] = (row["seconds"] as? Double ?? .infinity) <= 8
            }
            checked.append(result)
        }
        let destination = URL(fileURLWithPath: resultsPath).deletingPathExtension().appendingPathExtension("checked.json")
        try JSONSerialization.data(withJSONObject: ["results": checked], options: [.prettyPrinted, .sortedKeys])
            .write(to: destination, options: .atomic)
    }

    /// Frozen pre-integration dictation gate, for reproducing before/after acceptance.
    private static func baselineAccepts(_ original: String, _ candidate: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().replacingOccurrences(of: "’", with: "'")
                .split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
        }
        func numbers(_ text: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: #"\d+(?:[.,:]\d+)*"#)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= max(80, original.count * 2) else { return false }
        let input = words(original), output = words(value)
        guard !input.isEmpty, !output.isEmpty else { return false }
        let ratio = Double(output.count) / Double(input.count)
        guard ratio >= 0.3, ratio <= 1.7 else { return false }
        let vocabulary = Set(input)
        let grammar: Set<String> = ["a", "an", "the", "and", "but", "or", "so", "to", "of", "in", "on", "at", "as", "is", "are", "was", "were", "be", "been", "being"]
        guard output.allSatisfy({ vocabulary.contains($0) || grammar.contains($0) }) else { return false }
        let forbidden = ["here is the", "here's the", "as an ai", "i cannot help", "cleaned transcript:", "<think>"]
        guard !forbidden.contains(where: { value.lowercased().hasPrefix($0) }) else { return false }
        let inputNumbers = numbers(original), outputNumbers = numbers(value)
        let correction = ["actually", "correction", "no wait", "i mean", "make that", "scratch that"].contains { original.lowercased().contains($0) }
        if correction {
            guard outputNumbers.allSatisfy({ inputNumbers.contains($0) }) else { return false }
        } else if inputNumbers.sorted() != outputNumbers.sorted() { return false }
        let negatives: Set<String> = ["not", "never", "don't", "doesn't", "didn't", "can't", "cannot", "won't", "isn't", "wasn't"]
        if !correction && input.contains(where: negatives.contains) && !output.contains(where: negatives.contains) { return false }
        return true
    }

    @Test @MainActor
    func exportRequests() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let destination = environment["MURMUR_WRITING_BENCHMARK_EXPORT"],
              let corpusPath = environment["MURMUR_WRITING_BENCHMARK_CORPUS"] else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: corpusPath))
        let corpus = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(corpus["cases"] as? [[String: Any]])
        var requests: [[String: Any]] = []
        for item in cases {
            let source = try #require(item["source"] as? String)
            let operation = try #require(item["operation"] as? String)
            let system: String
            let user: String
            let maxTokens: Int
            let context = item["context"] as? [String: Any] ?? [:]
            if operation.hasPrefix("dictation_") {
                let style = try #require(WritingStyle.find(String(operation.dropFirst("dictation_".count))))
                let profile = WritingContext(styleID: style.id, styleName: style.name,
                    instruction: style.instruction, memory: "", examples: [])
                system = TextProcessingService.cleanupPrompt(profile: profile, vocabulary: [])
                user = String(decoding: try JSONSerialization.data(withJSONObject:
                    ["transcript": DictationIntent.apply(source), "nearCursor": ""], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
                maxTokens = min(1_200, max(128, source.count / 2 + 64))
            } else {
                let action = try #require(WritingAction(rawValue: operation))
                let style = try #require(WritingStyle.find(action.personalizationStyleID ?? context["app_default_style"] as? String ?? "clean"))
                let profile = WritingContext(styleID: style.id, styleName: style.name, instruction: style.instruction,
                    memory: context["memory"] as? String ?? "", examples: [])
                let request = try WritingAssistantService.request(action: action, source: source,
                    instruction: item["instruction"] as? String ?? "", profile: profile)
                system = request.system
                user = request.user
                maxTokens = 3_072
            }
            requests.append(["id": item["id"]!, "operation": operation, "source": source,
                "system": system, "user": user, "max_tokens": maxTokens,
                "must_preserve": item["must_preserve"] ?? [], "must_not": item["must_not"] ?? []])
        }
        try JSONSerialization.data(withJSONObject: ["requests": requests], options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: destination), options: .atomic)
    }
}
