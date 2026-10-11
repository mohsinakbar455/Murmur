import Foundation

/// Deterministically removes user-selected filler words and short phrases from a transcript.
///
/// The filter deliberately owns only deletion and the whitespace repair caused by deletion.
/// Punctuation, capitalization, and spoken commands remain the formatter's responsibility.
public struct FillerWordFilter: Sendable {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let removalCount: Int

        public init(text: String, removalCount: Int) {
            self.text = text
            self.removalCount = removalCount
        }
    }

    private struct Rule: Sendable {
        let regex: NSRegularExpression
    }

    private let rules: [Rule]

    public init(words: [String]) {
        var seen = Set<String>()
        let normalized = words.compactMap(Self.normalize)
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }

        rules = normalized.compactMap { word in
            let parts = word
                .split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !parts.isEmpty else { return nil }

            // A saved phrase also matches the joined/hyphenated forms speech engines
            // occasionally produce. Apostrophes are treated as word characters so a rule
            // cannot bite into a possessive or contraction.
            let body = parts.joined(separator: "[\\s\\-]*")
            let pattern = "(?<![\\p{L}\\p{N}'’])\(body)(?![\\p{L}\\p{N}'’]),?"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { return nil }
            return Rule(regex: regex)
        }
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Trims, folds whitespace, normalizes Unicode, and lowercases a saved entry.
    public static func normalize(_ candidate: String) -> String? {
        let normalized = candidate
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    public func apply(to text: String) -> Result {
        guard !text.isEmpty, !rules.isEmpty else {
            return Result(text: text, removalCount: 0)
        }

        var result = text.precomposedStringWithCanonicalMapping
        var removalCount = 0

        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            let matches = rule.regex.numberOfMatches(in: result, range: range)
            guard matches > 0 else { continue }
            removalCount += matches
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: ""
            )
        }

        result = Self.repairWhitespace(in: result)
        if !result.unicodeScalars.contains(where: {
            CharacterSet.alphanumerics.contains($0)
        }) {
            result = ""
        }

        return Result(text: result, removalCount: removalCount)
    }

    private static func repairWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
