import Foundation

/// A snapshot for one dictation. Saved context is data, never a replacement for the
/// formatter's transcript-preservation rules.
struct WritingContext: Sendable, Equatable {
    let styleID: String
    let styleName: String
    let instruction: String
    let memory: String
    let examples: [WritingExample]

    /// A deterministic input-size ceiling. The inference provider must additionally
    /// enforce its own tokenizer/context-window limit when building the full prompt.
    var utf8ByteCount: Int {
        instruction.utf8.count + memory.utf8.count
            + examples.reduce(0) { $0 + $1.raw.utf8.count + $1.corrected.utf8.count }
    }
}

struct WritingStyle: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let summary: String
    let instruction: String
    let sample: String

    static let builtIns: [WritingStyle] = [
        WritingStyle(
            id: "faithful", name: "Faithful",
            summary: "Your words, with punctuation and capitalization.",
            instruction: "Keep the speaker's wording and intentional repetitions. Fix punctuation and capitalization only. Do not paraphrase, summarize, add facts, or answer the transcript.",
            sample: "I think we should send the draft today, and then review it tomorrow."
        ),
        WritingStyle(
            id: "clean", name: "Clean",
            summary: "Natural sentences with clear spoken corrections.",
            instruction: "Make the transcript easy to read while keeping the speaker's words and tone. Apply explicit spoken self-corrections and repair obvious false starts. Preserve every fact, name, number and negation. Do not answer or expand the transcript.",
            sample: "We should send the draft today and review it tomorrow."
        ),
        WritingStyle(
            id: "professional", name: "Professional",
            summary: "Clear, composed writing for work.",
            instruction: "Use a clear, professional tone without making the text formal or verbose. You may lightly rephrase conversational wording. Preserve the speaker's intent, uncertainty, facts, names, numbers and negations. Add no greetings, promises, facts or answers that were not spoken.",
            sample: "Let's send the draft today and review it tomorrow."
        ),
        WritingStyle(
            id: "casual", name: "Casual",
            summary: "Conversational writing that still sounds like you.",
            instruction: "Keep a relaxed, conversational tone and natural contractions. Preserve the speaker's meaning, facts, names, numbers and negations. Do not invent slang, emojis, greetings, or answers. Apply explicit spoken self-corrections.",
            sample: "Let's send the draft today, then take a look tomorrow."
        ),
    ]

    static func find(_ id: String) -> WritingStyle? {
        builtIns.first { $0.id == id }
    }
}

struct WritingAppRule: Identifiable, Codable, Sendable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var appName: String
    var styleID: String
}

struct WritingMemory: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var text: String
    /// nil means all apps. A scoped note never crosses into another app's prompt.
    var bundleID: String?
    var appName: String?
    var isEnabled: Bool = true
    var createdAt: Date = Date()
}

struct WritingExample: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var raw: String
    var corrected: String
    var bundleID: String? = nil
    var appName: String? = nil
    var styleID: String = "clean"
    var isEnabled: Bool = true
    var createdAt: Date = Date()
}
