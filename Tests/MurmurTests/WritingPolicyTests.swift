import Foundation
import Testing
@testable import Murmur

@Suite("Murmur writing fidelity and personalization")
struct WritingPolicyTests {
    @Test("Grammar edits can introduce needed words without inventing content")
    func grammar() {
        #expect(TranscriptOutputCheck.accepts(original: "she don't want it", candidate: "She doesn't want it."))
        #expect(TranscriptOutputCheck.accepts(original: "I'm gonna send it", candidate: "I'm going to send it."))
        #expect(!TranscriptOutputCheck.accepts(original: "say hi to bob", candidate: "Say hi to Tom."))
        #expect(!TranscriptOutputCheck.accepts(original: "send the invoice", candidate: "Do not send the invoice."))
        #expect(TranscriptOutputCheck.accepts(original: "Don't send the invoice", candidate: "Don't send the invoice."))
        #expect(TranscriptOutputCheck.accepts(original: "send over 3000 tomorrow", candidate: "Send over 3,000 tomorrow."))
        #expect(TranscriptOutputCheck.accepts(original: "we have 3 open questions", candidate: "We have three open questions."))
        #expect(WritingOutputCheck.concern(source: "Send one hundred.", candidate: "Send 1.") != nil)
        #expect(WritingOutputCheck.concern(source: "Send 1.", candidate: "Send twenty one.") != nil)
    }

    @Test("Uncertainty and genuine greetings survive automatic cleanup")
    func voiceAndUncertainty() {
        #expect(!TranscriptOutputCheck.accepts(original: "maybe John will send it Thursday", candidate: "John will send it Thursday."))
        #expect(TranscriptOutputCheck.accepts(original: "I hope this helps let me know if Thursday works",
            candidate: "I hope this helps. Let me know if Thursday works."))
        #expect(WritingOutputCheck.concern(source: "شاید علی کل آئے۔", candidate: "علی کل آئے۔") != nil)
        #expect(WritingOutputCheck.concern(source: "shayad Ali kal aaye", candidate: "Ali kal aaye") != nil)
    }

    @Test("Only the locally corrected quantity may disappear")
    func localCorrections() {
        #expect(TranscriptOutputCheck.accepts(original: "send 250 tomorrow actually make that 350", candidate: "Send 350 tomorrow."))
        #expect(TranscriptOutputCheck.accepts(original: "send 250 no wait 350", candidate: "Send 350."))
        #expect(!TranscriptOutputCheck.accepts(original: "actually I do not approve the 250 dollar expense", candidate: "I approve the expense."))
        #expect(!TranscriptOutputCheck.accepts(original: "do not send the invoice send 250 tomorrow actually make that 350", candidate: "Send the invoice. Send 350 tomorrow."))
    }

    @Test("Numeric bounds survive while harmless thousands formatting is accepted")
    func bounds() {
        #expect(WritingOutputCheck.concern(source: "over 3000 square feet", candidate: "more than 3,000 square feet") == nil)
        #expect(WritingOutputCheck.concern(source: "around 3000 dollars", candidate: "around $3,000") == nil)
        #expect(WritingOutputCheck.concern(source: "over 3 days", candidate: "over three days") == nil)
        #expect(WritingOutputCheck.concern(source: "over 3000 square feet", candidate: "3000 square feet") != nil)
        #expect(WritingOutputCheck.concern(source: "at least 20 people", candidate: "at most 20 people") != nil)
        #expect(WritingOutputCheck.concern(source: "3,5 litres", candidate: "35 litres") != nil)
    }

    @Test("Participant order, literal spans, and unique capabilities are protected")
    func protectedContent() {
        #expect(!TranscriptOutputCheck.accepts(original: "Sarah owes John 50 dollars", candidate: "John owes Sarah 50 dollars."))
        #expect(WritingOutputCheck.concern(source: "Run `tool --dry-run`", candidate: "Run `tool dry run`.") != nil)
        #expect(WritingOutputCheck.concern(source: "Only our tool updates both records simultaneously.", candidate: "Our tool updates both records.") != nil)
        #expect(WritingOutputCheck.concern(source: "This is our only tool.", candidate: "This is the only tool.") != nil)
    }

    @Test("Summary can omit details; custom edits can change facts explicitly")
    func actionContracts() {
        #expect(WritingOutputCheck.concern(source: "We met at 9 for 2 hours. No decision.",
            candidate: "No decision was made.", permitsOmission: true) == nil)
        #expect(WritingOutputCheck.concern(source: "We met at 9.", candidate: "We met at 10.", permitsOmission: true) != nil)
        #expect(WritingOutputCheck.concern(source: "Meet at 9.", candidate: "Meet at 10.", permitsExplicitChange: true) == nil)
        #expect(WritingOutputCheck.assistantConcern(action: .table, source: "No deadline was given for the draft.",
            candidate: "| Item | Deadline |\n| --- | --- |\n| Draft | |") == nil)
        #expect(WritingOutputCheck.assistantConcern(action: .table, source: "No deadline was given. Do not send the draft.",
            candidate: "| Item | Deadline |\n| --- | --- |\n| Send draft | |") != nil)
    }

    @Test("An explicit action selects matching examples without leaking app scope")
    @MainActor
    func actionContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalizationStore(fileURL: directory.appendingPathComponent("prefs.json"))
        #expect(store.setAppRule(bundleID: "test.chat", appName: "Chat", styleID: "casual"))
        #expect(store.saveCorrection(raw: "casual before", corrected: "casual after", bundleID: "test.chat", styleID: "casual", remember: true))
        #expect(store.saveCorrection(raw: "work before", corrected: "work after", bundleID: "test.chat", styleID: "professional", remember: true))
        #expect(store.saveMemory(text: "private note", bundleID: "test.other", appName: "Other"))
        let context = store.context(for: "test.chat", styleID: WritingAction.professional.personalizationStyleID)
        #expect(context.styleID == "professional")
        #expect(context.examples.map(\.raw) == ["work before"])
        #expect(!context.memory.contains("private note"))
        #expect(store.context(for: nil).examples.isEmpty)
    }

    @Test("Optional context is bounded and oversized examples are omitted whole")
    func boundedContext() throws {
        let style = WritingStyle.builtIns[1]
        let profile = WritingContext(styleID: style.id, styleName: style.name, instruction: style.instruction,
            memory: String(repeating: "語", count: 2_000), examples: [
                WritingExample(raw: String(repeating: "a", count: 4_000), corrected: "OMITTED"),
                WritingExample(raw: "small example", corrected: "Small example.")])
        let request = try WritingAssistantService.request(action: .rewrite, source: "Original source.", instruction: "", profile: profile)
        #expect(!request.system.contains("OMITTED"))
        #expect(!request.system.contains("語"))
        #expect(request.system.contains("small example"))
        #expect(request.system.utf8.count < 3_500)
        #expect(request.user.contains("Original source."))
        let proofread = try WritingAssistantService.request(action: .proofread, source: "Keep me.", instruction: "", profile: profile)
        #expect(!proofread.system.contains("small example"))
    }

    @Test("Default profiles do not add redundant instructions to benchmarked requests")
    func defaultPromptParity() throws {
        for action in WritingAction.allCases {
            let style = WritingStyle.find(action.personalizationStyleID ?? "clean")!
            let profile = WritingContext(styleID: style.id, styleName: style.name,
                instruction: style.instruction, memory: "", examples: [])
            #expect(WritingPolicy.assistant(action: action, profile: profile) == WritingPolicy.assistant(action: action, profile: nil))
        }
    }
}
