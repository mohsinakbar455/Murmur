import Foundation

enum WritingAction: String, CaseIterable, Identifiable, Sendable {
    case proofread, rewrite, friendly, professional, concise, summary, keyPoints, list, table, compose, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .proofread: "Proofread"
        case .rewrite: "Rewrite"
        case .friendly: "Friendly"
        case .professional: "Professional"
        case .concise: "Concise"
        case .summary: "Summary"
        case .keyPoints: "Key Points"
        case .list: "List"
        case .table: "Table"
        case .compose: "Compose"
        case .custom: "Custom change"
        }
    }
    var instruction: String {
        switch self {
        case .proofread: "Correct grammar, spelling and punctuation. Make minimal edits. Preserve tone, meaning, names, quantities and paragraph structure. If already correct, return the original text unchanged."
        case .rewrite: "Rewrite for clarity and natural flow. Preserve all facts, meaning, names, numbers and intent."
        case .friendly: "Make the wording warm, friendly and natural. Preserve facts, names, quantities and intent. Do not add greetings, promises or invented personal details."
        case .professional: "Use professional, respectful, clear language. Preserve facts, names, quantities and intent. Avoid unnecessary jargon and embellishment."
        case .concise: "Shorten the writing by removing repetition and unnecessary words. Preserve essential facts, qualifications, names, quantities and intent."
        case .summary: "Summarize the main ideas in a short paragraph. Preserve uncertainty and important qualifications. Do not add facts."
        case .keyPoints: "Extract the important points as concise bullet points. Preserve important qualifications. Do not invent points or commitments."
        case .list: "Reformat the supplied items into a clear bullet list. Keep the supplied details and order. Do not invent new items. Put each item on its own line starting with '- '."
        case .table: "Organize the supplied information into a Markdown table with appropriate column headings. Use only supplied facts. Leave unknown cells empty, even when the source says no value was given. Return only the table, without code fences."
        case .compose: "Draft the text requested by the user's instruction. Use the source text as reference material. Do not invent factual details such as names, dates, prices or promises; use placeholders when necessary."
        case .custom: "Edit the source text according to the user's change instruction. Preserve facts unless the instruction explicitly requests a change."
        }
    }
    var needsInstruction: Bool { self == .custom || self == .compose }
}

struct WritingAssistantError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

enum WritingAssistantService {
    // The local runtime has an 8K context. Bound both source and instruction explicitly;
    // never silently truncate the user's selection.
    static let maximumSourceLength = 6_000
    static let maximumInstructionLength = 1_000

    static func request(action: WritingAction, source: String, instruction: String,
                        profile: WritingContext? = nil) throws -> (system: String, user: String) {
        guard source.utf8.count <= maximumSourceLength else {
            throw WritingAssistantError(message: "This passage is too long. Select a smaller section and try again.")
        }
        guard instruction.utf8.count <= maximumInstructionLength else {
            throw WritingAssistantError(message: "Shorten your instruction and try again.")
        }
        guard action == .compose || !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAssistantError(message: "Select or paste text to edit first.")
        }
        guard !action.needsInstruction || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAssistantError(message: "Describe what you want to write or change.")
        }
        let system = WritingPolicy.assistant(action: action, profile: profile)
        let change = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep both obligations together: small local models otherwise tend to
        // perform only the additional change and skip the selected action.
        let combinedInstruction = !action.needsInstruction && !change.isEmpty
            ? "\(action.title). Also: \(change)"
            : change
        let data = try JSONSerialization.data(withJSONObject: [
            "source_text": source,
            "change_instruction": combinedInstruction
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        return (system, String(decoding: data, as: UTF8.self))
    }

    static func checkedOutput(_ output: String) throws -> String {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 24_000, !text.contains("<think>") else {
            throw WritingAssistantError(message: "The model returned an empty or oversized result. Your original text was kept.")
        }
        return text
    }

    static func preservingBoundaryWhitespace(source: String, result: String) -> String {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }
        let prefix = source.prefix(while: \.isWhitespace)
        let suffix = source.reversed().prefix(while: \.isWhitespace).reversed()
        return String(prefix) + result + String(suffix)
    }

    @MainActor
    static func perform(action: WritingAction, source: String, instruction: String,
                        profile: WritingContext? = nil) async throws -> String {
        let prompt = try request(action: action, source: source, instruction: instruction, profile: profile)
        guard let model = WritingModelManager.shared.selectedModelURL else {
            throw WritingAssistantError(message: "Download and select a Qwen model in Models → Writing & cleanup.")
        }
        guard LocalTextRuntime.runtimeAvailable else { throw LocalTextRuntimeError.runtimeMissing }
        let output = try await LocalTextRuntime.shared.complete(modelURL: model, system: prompt.system,
            user: prompt.user, maxTokens: 3_072, timeoutSeconds: 90)
        try Task.checkCancellation()
        let text = preservingBoundaryWhitespace(source: source, result: try checkedOutput(output))
        if let reason = WritingOutputCheck.assistantConcern(action: action, source: source, candidate: text) {
            throw WritingReviewRequired(text: text, reason: reason)
        }
        return text
    }
}
