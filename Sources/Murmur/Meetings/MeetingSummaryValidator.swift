import Foundation

/// Structural evidence validation is deliberately conservative. It can establish that a
/// citation and named owner occur in the source, but cannot prove the model understood it.
enum MeetingSummaryValidator {
    enum Failure: LocalizedError {
        case unsupportedCitation(String)
        case missingCitation
        case actionNeedsOwner
        case unsupportedOwner(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedCitation(let citation): "The draft referenced a timestamp that is not in this transcript (\(citation)). It was not saved. Please regenerate."
            case .missingCitation: "The draft contained a factual line without a transcript citation. It was not saved. Please regenerate."
            case .actionNeedsOwner: "The draft did not clearly identify an action's owner or mark it Unassigned. It was not saved. Please regenerate."
            case .unsupportedOwner(let owner): "The draft assigned an action to \(owner), but that owner was not supported by its cited lines. It was not saved. Please regenerate."
            }
        }
    }

    static func validate(_ summary: String, against meeting: MeetingRecord) throws {
        let sources = meeting.orderedSegments.filter { $0.issue == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let citationExpression = try NSRegularExpression(pattern: #"\[[^\]\r\n]*[0-9]:[0-9][^\]\r\n]*\]"#)
        var actions = false
        for raw in summary.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { actions = line.lowercased().contains("action"); continue }
            let content = line.trimmingCharacters(in: CharacterSet(charactersIn: "-* ."))
            if content.lowercased() == "none recorded" { continue }
            let matches = citationExpression.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else { throw Failure.missingCitation }
            var cited: [MeetingSegment] = []
            for match in matches {
                let token = (line as NSString).substring(with: match.range)
                let time = String(token.dropFirst().dropLast()).replacingOccurrences(of: "—", with: "–").replacingOccurrences(of: "-", with: "–")
                let supported = sources.filter { segment in
                    time == MeetingExport.clock(segment.start) || time == "\(MeetingExport.clock(segment.start))–\(MeetingExport.clock(segment.end))"
                }
                guard !supported.isEmpty else { throw Failure.unsupportedCitation(token) }
                cited.append(contentsOf: supported)
            }
            if actions {
                guard let colon = content.firstIndex(of: ":") else { throw Failure.actionNeedsOwner }
                let owner = String(content[..<colon]).replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
                guard !owner.contains("["), !owner.isEmpty, owner.count <= 60 else { throw Failure.actionNeedsOwner }
                if owner.caseInsensitiveCompare("Unassigned") == .orderedSame { continue }
                if let channel = MeetingSpeaker.allCasesForValidation.first(where: { $0.rawValue.caseInsensitiveCompare(owner) == .orderedSame }) {
                    guard cited.contains(where: { $0.speaker == channel }) else { throw Failure.unsupportedOwner(owner) }
                    continue
                }
                let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: owner) + #"(?![\p{L}\p{N}])"#
                guard cited.contains(where: { $0.text.range(of: pattern, options: .regularExpression) != nil }) else { throw Failure.unsupportedOwner(owner) }
            }
        }
    }
}

private extension MeetingSpeaker {
    static var allCasesForValidation: [MeetingSpeaker] { [.you, .remote] }
}
