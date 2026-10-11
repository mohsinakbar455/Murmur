import Foundation

/// Fast conservative checks, not a proof of semantic equivalence. A failed check
/// prevents automatic delivery; no extra model call is made to repair an answer.
enum WritingOutputCheck {
    static func concern(source: String, candidate: String, permitsOmission: Bool = false,
                        permitsExplicitChange: Bool = false, speechCorrections: Bool = false,
                        permitsEmptyTableCells: Bool = false) -> String? {
        let input = normalized(source), output = normalized(candidate)
        if candidate.contains("<think>") || candidate.contains("</think>") { return "The result contains model commentary." }
        for prefix in ["here is the revised", "here's the revised", "as an ai", "cleaned transcript:"] {
            if output.hasPrefix(prefix), !input.hasPrefix(prefix) { return "The model added commentary." }
        }
        // Custom transformations may explicitly request translation or factual edits.
        guard !permitsExplicitChange else { return nil }
        for literal in matches(#"`[^`\n]+`|https?://[^\s<>]+|(?<![\w:])/(?:[\w.~-]+/)*[\w.~-]+"#, in: source) {
            let protected = literal.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?"))
            if !candidate.contains(protected), !permitsOmission { return "A code fragment, link or path changed." }
        }
        var preservedInput = speechCorrections ? resolvingNumericCorrections(input) : input
        // In a table, an empty cell legitimately expresses an explicitly missing
        // value. Other prohibitions in the same source must still be checked.
        if permitsEmptyTableCells, !matches(#"\|[ \t]*\|"#, in: output).isEmpty {
            preservedInput = preservedInput.replacingOccurrences(
                of: #"\bno (?:deadline|due date|date|time|owner|price|value) (?:(?:was|is|has been) )?(?:given|provided|specified|set|assigned|recorded)\b"#,
                with: "unspecified", options: .regularExpression)
        }
        let writtenValues = Set(numbers(preservedInput) + numbers(output))
        let expected = numbers(preservedInput, spelledValues: writtenValues)
        let actual = numbers(output, spelledValues: writtenValues)
        if permitsOmission {
            var available = expected
            for number in actual {
                guard let index = available.firstIndex(of: number) else { return "The result added a quantity." }
                available.remove(at: index)
            }
        } else if expected.sorted() != actual.sorted() { return "A quantity changed or disappeared." }
        guard !permitsOmission else { return nil }

        // Canonicalize common equivalent forms without deleting uncertainty cues.
        let groups = [
            #"\b(?:not|never|no|cannot|without)\b|\b\w+n't\b|\b(?:nahi|nahin|mat)\b|نہیں|مت"#,
            #"\b(?:maybe|perhaps|might|may|possibly|probably|likely|tentatively|uncertain|unsure|shayad)\b|شاید"#,
            #"\b(?:if|unless|provided|assuming|agar)\b|اگر"#,
            #"\b(?:only|sole|solely|sirf)\b|صرف"#,
            #"\b(?:simultaneously|concurrently|at once|at the same time)\b"#
        ]
        for pattern in groups {
            if matches(pattern, in: preservedInput).isEmpty != matches(pattern, in: output).isEmpty {
                return "A qualification, condition or negation may have changed."
            }
        }
        // Preserve numeric bounds, not just the digits.
        let bounds = [#"\b(?:over|more than|greater than|above)\s+\d"#,
                      #"\b(?:under|less than|below|fewer than)\s+\d"#,
                      #"\b(?:at least|no less than)\s+\d"#,
                      #"\b(?:at most|up to|no more than)\s+\d"#,
                      #"\b(?:about|around|approximately|roughly)\s+\d"#]
        let amount = #"(?:[$€£]\s*)?(?:\d|(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b)"#
        for bound in bounds {
            let pattern = bound.replacingOccurrences(of: #"\d"#, with: amount)
            if matches(pattern, in: input).count != matches(pattern, in: output).count {
                return "A quantity's bound or approximation changed."
            }
        }
        if words(input).contains("only"), words(input).contains("our"),
           !words(output).contains("our"), !words(output).contains("we") {
            return "A claim limited to your own tools or team may have been broadened."
        }
        return nil
    }

    static func assistantConcern(action: WritingAction, source: String, candidate: String) -> String? {
        concern(source: source, candidate: candidate,
            permitsOmission: action == .summary || action == .keyPoints,
            permitsExplicitChange: action == .custom || action == .compose,
            permitsEmptyTableCells: action == .table)
    }

    static func acceptsTranscript(_ source: String, _ candidate: String, styleID: String) -> Bool {
        let prepared = DictationIntent.apply(source)
        let expectedEmoji = DictationIntent.emojiCharacters(prepared)
        guard expectedEmoji == DictationIntent.emojiCharacters(candidate) else { return false }
        let items = DictationIntent.listItems(prepared)
        if !items.isEmpty {
            // Formatting must never drop, merge, reorder or paraphrase list items.
            guard items.map(words) == DictationIntent.listItems(candidate).map(words) else { return false }
        }
        let source = DictationIntent.withoutListMarkers(prepared)
        let candidate = DictationIntent.withoutListMarkers(candidate)
        if words(source).isEmpty, !expectedEmoji.isEmpty {
            return normalized(source).trimmingCharacters(in: .whitespacesAndNewlines)
                == normalized(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= max(80, source.count * 2),
              concern(source: source, candidate: value, speechCorrections: true) == nil else { return false }
        let input = words(source), output = words(value)
        guard !input.isEmpty, !output.isEmpty else { return false }
        let ratio = Double(output.count) / Double(input.count)
        guard ratio >= 0.3, ratio <= 1.7 else { return false }
        let sourceWords = Set(input.map(stem))
        let novel = output.filter { !sourceWords.contains(stem($0)) && !grammar.contains($0) }
        // Clean is deliberately close to the source. Explicit tone styles permit a
        // small paraphrase budget; names, quantities and qualifications stay checked.
        let allowance = ["professional", "casual"].contains(styleID) ? input.count / 5 : 0
        guard novel.count <= allowance else { return false }
        let names = capitalizedWords(source).filter { !sentenceWords.contains($0.lowercased()) }
        for name in names where !output.contains(name.lowercased()) { return false }
        for name in capitalizedWords(value) where !input.contains(name.lowercased()) && !sentenceWords.contains(name.lowercased()) {
            return false
        }
        // Preserve participant order in automatic dictation. Explicit Rewrite is freer.
        let nameSet = Set(names.map { $0.lowercased() })
        if input.filter(nameSet.contains) != output.filter(nameSet.contains) { return false }
        let questions: Set<String> = ["what", "why", "where", "when", "who", "how", "can", "could", "would"]
        if let first = input.first, questions.contains(first), !value.contains("?") { return false }
        return true
    }

    private static let grammar: Set<String> = [
        "a", "an", "the", "and", "but", "or", "so", "to", "of", "in", "on", "at", "as", "is", "are",
        "was", "were", "be", "been", "being", "do", "does", "did", "have", "has", "had", "am",
        "i'm", "i've", "i'll", "it's", "that's", "there's", "we're", "we've", "you're", "they're",
        "don't", "doesn't", "didn't", "can't", "cannot", "won't", "isn't", "wasn't", "not", "going"
    ]
    private static let sentenceWords = grammar.union([
        "please", "maybe", "perhaps", "hi", "hello", "dear", "thanks", "thank", "i", "we", "you", "he", "she", "they", "it",
        "this", "these", "those", "that", "my", "our", "your", "his", "her", "their", "send", "use", "run", "let", "let's",
        "actually", "what", "why", "where", "when", "who", "how", "can", "could", "would", "tomorrow", "today"
    ]).union(numberWords.keys)
    private static let numberWords = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12"]
    private static let compoundNumbers: Set<String> = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "point"]
    private static func capitalizedWords(_ text: String) -> [String] {
        matches(#"\b\p{Lu}[\p{L}\p{M}'’]*\b"#, in: text)
    }
    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "’", with: "'")
    }
    private static func words(_ text: String) -> [String] {
        var value = normalized(text)
        for number in matches(#"\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b"#, in: value) {
            value = value.replacingOccurrences(of: number, with: number.replacingOccurrences(of: ",", with: ""))
        }
        return value.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { numberWords[String($0)] ?? String($0) }
    }
    private static func stem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
    private static func numbers(_ text: String, spelledValues: Set<String> = []) -> [String] {
        let tokens = matches(#"\d+(?:[.,:]\d+)*|[a-z]+"#, in: text)
        return tokens.enumerated().compactMap { index, number in
            if let value = numberWords[number] {
                guard spelledValues.contains(value),
                      index == 0 || !compoundNumbers.contains(tokens[index - 1]),
                      index + 1 == tokens.count || !compoundNumbers.contains(tokens[index + 1]) else { return nil }
                return value
            }
            guard number.first?.isNumber == true else { return nil }
            // Recognize unambiguous grouping; preserve decimal commas such as 3,5.
            return number.range(of: #"^\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, options: .regularExpression) != nil
                ? number.replacingOccurrences(of: ",", with: "") : number
        }
    }
    private static func resolvingNumericCorrections(_ text: String) -> String {
        // Only a local explicit numeric replacement can discard a number. The word
        // "actually" elsewhere never disables preservation checks for the passage.
        let pattern = #"\b\d+(?:[.,:]\d+)*(?:\s+(?:dollars|euros|pounds|today|tomorrow)){0,2}[,\s]+(?:actually\s+)?(?:make that|no wait|i mean|correction)[,\s]+(\d+(?:[.,:]\d+)*)"#
        return text.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}

struct WritingReviewRequired: Error {
    let text: String
    let reason: String
}
