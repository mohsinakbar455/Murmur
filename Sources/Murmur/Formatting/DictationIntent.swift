import Foundation

/// Resolve unambiguous spoken formatting before cleanup so every engine, including
/// the offline fallback, sees the same content. Ambiguous prose stays with the model.
enum DictationIntent {
    static func apply(_ text: String) -> String {
        lists(emoji(text))
    }

    private static let emojiNames: [String: String] = [
        "fire": "🔥", "thumbs up": "👍", "thumbs down": "👎", "red heart": "❤️", "heart": "❤️",
        "broken heart": "💔", "blue heart": "💙", "laughing crying": "😂", "laugh cry": "😂",
        "tears of joy": "😂", "laughing": "😂", "rolling on the floor laughing": "🤣",
        "smile": "😊", "smiley": "😊", "smiling face": "😊", "wink": "😉", "winking face": "😉",
        "sad face": "😢", "crying face": "😢", "loudly crying": "😭", "heart eyes": "😍",
        "thinking face": "🤔", "eye roll": "🙄", "sunglasses": "😎", "party popper": "🎉",
        "celebration": "🎉", "rocket": "🚀", "sparkles": "✨", "star": "⭐", "check mark": "✅",
        "checkmark": "✅", "clapping hands": "👏", "clap": "👏", "folded hands": "🙏",
        "praying hands": "🙏", "waving hand": "👋", "wave": "👋", "skull": "💀", "eyes": "👀",
        "happy": "😊", "sad": "😢", "crying": "😢", "shrug": "🤷", "party": "🎉",
        "check": "✅", "cross": "❌", "coffee": "☕", "pizza": "🍕", "cake": "🎂",
        "dog": "🐶", "cat": "🐱", "hundred points": "💯", "100 points": "💯", "flexed biceps": "💪", "party face": "🥳"
    ]
    private static let emojiPattern: NSRegularExpression = {
        let names = emojiNames.keys.sorted { $0.count > $1.count }.map {
            NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"[ \t-]+"#)
        }.joined(separator: "|")
        return regex(#"\b(?:(?:add|insert|put)[ \t]+)?(?:(?:a|an|the)[ \t]+)?("# + names + #")[ \t-]+emoji\b"#)
    }()
    // Literal mentions and code must not be interpreted as commands. Apostrophes
    // inside contractions are deliberately excluded from the quoted-span pattern.
    private static let literalPattern = regex(#"```[\s\S]*?```|`[^`]*`|"[^"]*"|“[^”]*”|(?<!\w)'[^'\n]+'(?!\w)|‘[^’]*’|https?://\S+"#)
    private static let discussionPattern = regex(#"\b(?:word|words|phrase|literal|literally|called|named|means?|meaning|symbol|unicode|explain|describe|discuss|talk about|don't|do not|never|without)\b|\bnot[ \t]+(?:a|the|an|add|insert|use|send)\b|\b(?:want|need|how)[ \t]+to[ \t]+(?:add|insert|use)\b|\bwhat\b.*\bemoji\b|\bemoji\b[ \t]+(?:is|was|looks|represents)\b"#)

    static func emoji(_ text: String) -> String {
        let literals = literalPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        var result = text
        for match in emojiPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard !literals.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let start = text[..<range.lowerBound].lastIndex(where: { ".!?\n".contains($0) }).map { text.index(after: $0) } ?? text.startIndex
            let end = text[range.upperBound...].firstIndex(where: { ".!?\n".contains($0) }) ?? text.endIndex
            let sentence = String(text[start..<end]).replacingOccurrences(of: "’", with: "'")
            guard discussionPattern.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) == nil else { continue }
            let key = text[nameRange].lowercased().replacingOccurrences(of: #"[ \t-]+"#, with: " ", options: .regularExpression)
            guard let glyph = emojiNames[key] else { continue }
            // Use original UTF-16 ranges while replacing from right to left.
            result = (result as NSString).replacingCharacters(in: match.range, with: glyph)
        }
        return result
    }

    private static let shoppingLead = regex(#"^((?:i|we)[ \t]+(?:want|need)[ \t]+to[ \t]+(?:buy|get|pick up)|(?:please[ \t]+)?buy|(?:shopping|grocery|packing|to[ -]do)[ \t]+list)[ \t]*:?[ \t]+(.+)$"#)
    private static let enumeration = regex(#"\b(?:number[ \t]+(one|two|three|four|five|six|seven|eight|nine|ten)|((?:first|second|third|fourth|fifth)ly|(?:first|second|third|fourth|fifth)(?=[ \t]*,)))[ \t]*[,.:]?[ \t]+"#)
    private static let bullet = regex(#"\b(?:bullet point|dot point|next bullet|new bullet)[ \t]*[,.:]?[ \t]+"#)
    private static let ordinalValues = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5]

    static func lists(_ text: String) -> String {
        let literals = literalPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        var offset = 0
        return text.components(separatedBy: "\n").map { line in
            let lineRange = NSRange(location: offset, length: (line as NSString).length)
            defer { offset += lineRange.length + 1 }
            guard !literals.contains(where: { NSIntersectionRange($0, lineRange).length > 0 }) else { return line }
            // A regex cannot safely identify item boundaries inside quotes, code,
            // decimals or multiple sentences. Leave those to contextual cleanup.
            let range = NSRange(line.startIndex..., in: line)
            guard literalPattern.firstMatch(in: line, range: range) == nil,
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("- "),
                  line.range(of: #"^\s*\d+[.)]\s"#, options: .regularExpression) == nil else { return line }
            if let marked = markedList(line, pattern: enumeration, numbered: true) { return marked }
            if let marked = markedList(line, pattern: bullet, numbered: false) { return marked }
            guard let match = shoppingLead.firstMatch(in: line, range: range),
                  let leadRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line) else { return line }
            let body = String(line[bodyRange]).trimmingCharacters(in: .whitespaces)
            let content = body.hasSuffix(".") ? String(body.dropLast()) : body
            guard !content.contains(where: { ".!?;:\n".contains($0) }),
                  content.range(of: #"\d,\d"#, options: .regularExpression) == nil else { return line }
            var items = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard items.count >= 2 else { return line }
            if let last = items.last, last.lowercased().hasPrefix("and ") {
                items[items.count - 1] = String(last.dropFirst(4))
            } else if let last = items.last, let join = last.range(of: " and ", options: .caseInsensitive),
                      last.range(of: " and ", options: .caseInsensitive, range: join.upperBound..<last.endIndex) == nil {
                items.removeLast()
                items += [String(last[..<join.lowerBound]), String(last[join.upperBound...])]
            }
            guard items.count >= 3, items.allSatisfy({ !$0.isEmpty && $0.split(whereSeparator: \.isWhitespace).count <= 8 }),
                  !items.contains(where: { $0.range(of: #"\b(?:because|but|if|then|which|that|instead|sorry|actually)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) else { return line }
            return String(line[leadRange]) + ":\n" + items.map { "- " + $0 }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func markedList(_ text: String, pattern: NSRegularExpression, numbered: Bool) -> String? {
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count >= 2 else { return nil }
        let ns = text as NSString
        if numbered {
            for (index, match) in matches.enumerated() {
                let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                let marker = ns.substring(with: capture).lowercased().replacingOccurrences(of: "ly", with: "")
                guard ordinalValues[marker] == index + 1 else { return nil }
            }
            let lead = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespaces)
            // "my first ... second ..." is ordinary prose, not an enumeration.
            guard lead.isEmpty || lead.hasSuffix(":") || lead.hasSuffix(".") else { return nil }
        }
        var blocks: [String] = []
        let head = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespaces)
        if !head.isEmpty { blocks.append(head) }
        for (index, match) in matches.enumerated() {
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            guard !item.isEmpty else { return nil }
            blocks.append((numbered ? "\(index + 1). " : "- ") + item)
        }
        return blocks.joined(separator: "\n")
    }

    /// Strip only a complete consecutive list's presentation markers, so a label
    /// such as "2." never gets mistaken for a newly invented quantity by the gate.
    static func withoutListMarkers(_ text: String) -> String {
        let pattern = regex(#"(?m)^([ \t]*)(\d+)[.)][ \t]+"#)
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        if matches.count >= 2, matches.enumerated().allSatisfy({ index, match in
            Int((text as NSString).substring(with: match.range(at: 2))) == index + 1
        }) {
            for match in matches.reversed() { result = (result as NSString).replacingCharacters(in: match.range, with: "") }
        }
        return result.replacingOccurrences(of: #"(?m)^[ \t]*[-*•][ \t]+"#, with: "", options: .regularExpression)
    }

    static func emojiCharacters(_ text: String) -> [String] {
        text.filter { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        }.map(String.init)
    }

    static func listItems(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter {
            $0.range(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) != nil
        }.map { $0.replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression) }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // All patterns are compile-time constants or escaped dictionary keys.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
