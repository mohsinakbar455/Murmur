import Foundation
import Testing
@testable import Murmur

@Suite("Speech and writing safeguards")
struct SpeechPipelineTests {
    @Test("Silence closes speech windows without discarding the next utterance")
    func pauseBoundary() {
        var window = SpeechWindowBuffer()
        window.append(Array(repeating: 0.1, count: 24_000))
        #expect(!window.shouldCommit)
        window.append(Array(repeating: 0, count: 8_000))
        #expect(window.shouldCommit)
        let decodedPrefix = window.samples.count
        window.append(Array(repeating: 0.2, count: 4_000))
        window.removePrefix(decodedPrefix)
        #expect(window.samples.count == 4_000)
        #expect(window.hasSpeech)
        #expect(window.lastVoiceSample == 4_000)
        #expect(window.samples.allSatisfy { $0 == 0.2 })
    }

    @Test("Uninterrupted speech is bounded and pure silence is not decoded")
    func speechBound() {
        var speech = SpeechWindowBuffer()
        speech.append(Array(repeating: 0.1, count: 16_000 * 12))
        #expect(speech.shouldCommit)
        var silence = SpeechWindowBuffer()
        silence.append(Array(repeating: 0, count: 32_000))
        #expect(!silence.hasSpeech)
        silence.removePrefix(32_000)
        #expect(silence.samples.isEmpty)
        #expect(silence.lastVoiceSample == 0)
    }

    @Test("Cleanup cannot answer a question, invent amounts or remove negation")
    func outputChecks() {
        #expect(!TranscriptOutputCheck.accepts(original: "what is the capital of france", candidate: "The capital of France is Paris."))
        #expect(!TranscriptOutputCheck.accepts(original: "say hi to bob", candidate: "Say hi to Tom."))
        #expect(!TranscriptOutputCheck.accepts(original: "send 250 tomorrow", candidate: "Send 2500 tomorrow."))
        #expect(!TranscriptOutputCheck.accepts(original: "do not send the invoice", candidate: "Send the invoice."))
        #expect(!TranscriptOutputCheck.accepts(original: "send this message to alex tomorrow morning", candidate: "Alex."))
        #expect(TranscriptOutputCheck.accepts(original: "send 250 tomorrow actually make that 350", candidate: "Send 350 tomorrow."))
        #expect(TranscriptOutputCheck.accepts(original: "can you send the invoice tomorrow", candidate: "Can you send the invoice tomorrow?"))
    }

    @Test("Deadline returns before an uncooperative backend and ignores its late reply")
    func deadline() async {
        let started = ContinuousClock.now
        do {
            let _: String = try await AsyncDeadline.run(seconds: 0.04) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { continuation.resume(returning: "late") }
                }
            }
            Issue.record("Expired work was delivered")
        } catch { #expect(error is AsyncDeadline.Expired) }
        #expect(started.duration(to: .now) < .milliseconds(300))
    }

    @Test("Cancellation cannot publish the eventual model response")
    func cancelledDeadline() async {
        let task = Task {
            try await AsyncDeadline.run(seconds: 5) {
                try await Task.sleep(for: .seconds(3))
                return "must not insert"
            }
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled result delivered") }
        catch { #expect(error is CancellationError) }
    }

    @Test("Old history rows decode without new metadata")
    func legacyHistory() throws {
        let data = Data(#"{"date":"2026-09-27T00:00:00Z","engine":"Whisper","audioSeconds":10,"processSeconds":2,"text":"Hello."}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(DictationRun.self, from: data)
        #expect(run.text == "Hello.")
        #expect(run.rawText == nil)
        #expect(run.fallbackReason == nil)
    }
}
