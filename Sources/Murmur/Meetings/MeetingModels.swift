import Foundation

/// Capture scope is explicit. A failed app tap never expands to all Mac audio.
enum MeetingCaptureSource: Hashable, Sendable {
    case microphone
    case microphoneAndSystem
    case microphoneAndApp(bundleID: String, name: String)

    var label: String {
        switch self {
        case .microphone: "Microphone only"
        case .microphoneAndSystem: "Microphone + all Mac audio"
        case .microphoneAndApp(_, let name): "Microphone + \(name)"
        }
    }
    var includesSystemAudio: Bool { self != .microphone }
}

enum MeetingSpeaker: String, Codable, Sendable {
    case you = "You"
    case remote = "Remote"
}

struct MeetingSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var speaker: MeetingSpeaker
    var text: String
    var issue: String? = nil
}

struct MeetingActionItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var isDone = false
}

struct MeetingRecord: Identifiable, Codable, Equatable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var source: String
    var modelID: String
    var language: String
    var segments: [MeetingSegment] = []
    var notes = ""
    var draftSummary = ""
    var actionItems: [MeetingActionItem] = []
    var interrupted = false

    init(title: String, startedAt: Date = Date(), source: String, modelID: String, language: String) {
        self.title = title
        self.startedAt = startedAt
        self.source = source
        self.modelID = modelID
        self.language = language
    }

    /// Older documents retain their transcript while newly introduced fields take defaults.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "This meeting was saved by a newer Murmur version.")
        }
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endedAt = try values.decodeIfPresent(Date.self, forKey: .endedAt)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "Microphone only"
        modelID = try values.decodeIfPresent(String.self, forKey: .modelID) ?? "unknown"
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        segments = try values.decodeIfPresent([MeetingSegment].self, forKey: .segments) ?? []
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        draftSummary = try values.decodeIfPresent(String.self, forKey: .draftSummary) ?? ""
        interrupted = try values.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        actionItems = try values.decodeIfPresent([MeetingActionItem].self, forKey: .actionItems) ?? []
    }

    var orderedSegments: [MeetingSegment] {
        segments.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    }

    /// Every line is evidence-addressable. Gaps are never disguised as successful speech.
    var transcript: String {
        orderedSegments.map {
            "[\(MeetingExport.clock($0.start))–\(MeetingExport.clock($0.end))] \($0.speaker.rawValue): \($0.issue.map { "[Transcription gap: \($0)]" } ?? $0.text)"
        }.joined(separator: "\n")
    }

    var summaryInput: String {
        "Meeting: \(title)\nCapture: \(source)\nSpeaker labels identify audio channels, not individual remote participants.\n\n" + transcript
    }

    /// Extract only explicit action-list bullets; never infer new commitments from prose.
    mutating func acceptDraftSummary(_ summary: String) {
        draftSummary = summary
        var insideActions = false
        var extracted: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                insideActions = line.lowercased().contains("action")
                continue
            }
            guard insideActions, line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            var action = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            for marker in ["[ ] ", "[x] ", "[X] "] where action.hasPrefix(marker) { action = String(action.dropFirst(marker.count)) }
            guard !action.isEmpty, !action.lowercased().hasPrefix("none recorded"), action.lowercased() != "none" else { continue }
            if !extracted.contains(action) { extracted.append(action) }
        }
        actionItems = extracted.map { text in
            actionItems.first(where: { $0.text == text }) ?? MeetingActionItem(text: text)
        }
    }

    var actionChecklist: String {
        actionItems.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }.joined(separator: "\n")
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [title, notes, draftSummary, transcript].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum MeetingExport: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case text = "Text"
    case json = "JSON"
    case srt = "SRT"
    var id: Self { self }
    var fileExtension: String {
        switch self { case .markdown: "md"; case .text: "txt"; case .json: "json"; case .srt: "srt" }
    }
    func data(for meeting: MeetingRecord) throws -> Data {
        if self == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(meeting)
        }
        let output: String
        switch self {
        case .markdown:
            output = "# \(meeting.title)\n\n\(meeting.startedAt.formatted()) · \(meeting.source)\n\n## Draft meeting notes\n\n\(meeting.draftSummary.isEmpty ? "No notes generated." : meeting.draftSummary)\n\n## Your notes\n\n\(meeting.notes)\n\n## Action checklist\n\n\(meeting.actionChecklist)\n\n## Transcript\n\n\(meeting.transcript)\n"
        case .text:
            output = "\(meeting.title)\n\n\(meeting.draftSummary)\n\n\(meeting.notes)\n\nAction checklist\n\(meeting.actionChecklist)\n\n\(meeting.transcript)\n"
        case .srt:
            output = meeting.orderedSegments.enumerated().map { index, segment in
                let end = max(segment.start + 0.001, segment.end)
                let content = segment.issue == nil ? segment.text : "[Transcription unavailable]"
                let clean = content.split(whereSeparator: \.isNewline).joined(separator: "\n")
                return "\(index + 1)\n\(Self.subtitleTime(segment.start)) --> \(Self.subtitleTime(end))\n\(segment.speaker.rawValue): \(clean)\n"
            }.joined(separator: "\n")
        case .json: output = ""
        }
        return Data(output.utf8)
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func subtitleTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(((seconds.isFinite ? seconds : 0) * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", value / 3_600_000, value / 60_000 % 60, value / 1000 % 60, value % 1000)
    }
}
