import Testing
import Foundation
@testable import Murmur

@Suite("File Transcription Tests")
struct FileTranscriptionTests {

    @Test("Regional dictation locales map to Whisper language tokens")
    func regionalLanguage() {
        #expect(WhisperKitPool.decodingOptions(language: "en-US").language == "en")
        #expect(WhisperKitPool.decodingOptions(language: "ur-PK").language == "ur")
        #expect(WhisperKitPool.decodingOptions(language: "pt_BR").language == "pt")
        #expect(WhisperKitPool.decodingOptions(language: "auto").language == nil)
    }

    @Test("Auto language enables Whisper detection while a chosen language is forced")
    func whisperLanguageOptions() {
        let automatic = WhisperKitPool.decodingOptions(language: nil)
        #expect(automatic.detectLanguage)
        #expect(automatic.language == nil)
        let urdu = WhisperKitPool.decodingOptions(language: "ur")
        #expect(!urdu.detectLanguage)
        #expect(urdu.language == "ur")
        let hindi = WhisperKitPool.decodingOptions(language: "hi")
        #expect(!hindi.detectLanguage)
        #expect(hindi.language == "hi")
    }

    @Test("Roman script applies only to Hindi and Urdu parts and keeps other speech")
    @MainActor
    func romanScriptMixedLanguage() async throws {
        let model = URL(fileURLWithPath: "/private/tmp/model.gguf")
        var convertedLanguages: [String] = []
        let result = try await RomanScriptPresenter.prepare(
            parts: ["آپ کیسے ہیں؟", "Keep this in English.", "आप कैसे हैं?"],
            languages: ["ur", "en", "hi"], enabled: true, modelURL: model
        ) { _, language, _ in
            convertedLanguages.append(language)
            return "aap kaise hain?"
        }
        #expect(result.text == "aap kaise hain? Keep this in English. aap kaise hain?")
        #expect(result.applied)
        #expect(convertedLanguages == ["ur", "hi"])
    }

    @Test("Invalid conversion keeps the output in Roman script and preserves good passages")
    @MainActor
    func romanScriptRecoversFromInvalidPassage() async throws {
        let model = URL(fileURLWithPath: "/private/tmp/model.gguf")
        let result = try await RomanScriptPresenter.prepare(
            parts: ["آپ کیسے ہیں؟", "Keep this in English.", "आप कैसे हैं?"],
            languages: ["ur", "en", "hi"], enabled: true, modelURL: model
        ) { text, _, _ in
            text == "آپ کیسے ہیں؟" ? "Here is the English translation: How are you?" : "aap kaise hain?"
        }
        #expect(result.applied)
        #expect(result.warning != nil)
        #expect(result.text.contains("Keep this in English."))
        #expect(result.text.contains("aap kaise hain?"))
        #expect(!result.text.unicodeScalars.contains {
            (0x0600...0x06FF).contains($0.value) || (0x0900...0x097F).contains($0.value)
        })
        #expect(!RomanScriptPresenter.accepts(original: "آپ کیسے ہیں؟", candidate: "How are you?"))
        #expect(!RomanScriptPresenter.accepts(original: "میرے پاس 3 کتابیں ہیں", candidate: "mere paas 4 kitaabein hain"))
    }

    @Test("Script is converted even when a mixed audio chunk is labelled English")
    @MainActor
    func romanScriptChecksActualScript() async throws {
        let model = URL(fileURLWithPath: "/private/tmp/model.gguf")
        var requestedLanguage: String?
        let result = try await RomanScriptPresenter.prepare(
            parts: ["Keep this in English. آپ کیسے ہیں؟"],
            languages: ["en"], enabled: true, modelURL: model
        ) { _, language, _ in
            requestedLanguage = language
            return "Keep this in English. Aap kaise hain?"
        }
        #expect(result.applied)
        #expect(requestedLanguage == "ur")
        #expect(result.text == "Keep this in English. Aap kaise hain?")
    }

    @Test("Long invalid model output is retried in smaller spans")
    @MainActor
    func romanScriptRetriesLongPassage() async throws {
        let model = URL(fileURLWithPath: "/private/tmp/model.gguf")
        let longPart = Array(repeating: "آپ کیسے ہیں؟", count: 8).joined(separator: " ")
        var calls = 0
        let result = try await RomanScriptPresenter.prepare(
            parts: [longPart], languages: ["ur"], enabled: true, modelURL: model
        ) { text, _, _ in
            calls += 1
            if text.split(whereSeparator: \.isWhitespace).count > 16 { return "How are you?" }
            return Array(repeating: "aap kaise hain?", count: 4).joined(separator: " ")
        }
        #expect(calls == 3)
        #expect(result.applied)
        #expect(result.warning == nil)
        #expect(result.text == Array(repeating: "aap kaise hain?", count: 8).joined(separator: " "))
    }

    @Test("Roman script has no effect when turned off or when Auto detects English")
    @MainActor
    func romanScriptRespectsSelection() async throws {
        let model = URL(fileURLWithPath: "/private/tmp/model.gguf")
        let parts = ["آپ کیسے ہیں؟"]
        let off = try await RomanScriptPresenter.prepare(parts: parts, languages: ["ur"], enabled: false, modelURL: model) {
            _, _, _ in Issue.record("Conversion should not run when Roman script is off"); return ""
        }
        #expect(off.text == parts[0])
        let english = try await RomanScriptPresenter.prepare(parts: ["Hello there"], languages: ["en"], enabled: true, modelURL: model) {
            _, _, _ in Issue.record("Conversion should not run for English"); return ""
        }
        #expect(english.text == "Hello there")
        #expect(english.warning != nil)
    }

    @Test("Cleanup Off preserves the recognizer's exact transcript")
    @MainActor
    func cleanupOffPreservesRawTranscript() async {
        let raw = "um  hello, uh  world.\n<noise>  [inaudible]"
        let result = await TextProcessingService.shared.process(raw, mode: .off)
        #expect(result.text == raw)
        #expect(result.raw == raw)
    }

    @Test("File cleanup On attempts the writing model")
    @MainActor
    func cleanupOnUsesWritingModel() async {
        let missingModel = URL(fileURLWithPath: "/private/tmp/murmur-missing-\(UUID().uuidString).gguf")
        let result = await TextProcessingService.shared.processFileTranscript(
            "Please send the draft tomorrow.", mode: .smart, writingModelURL: missingModel
        )
        #expect(result.engine == "Rules fallback")
        #expect(result.fallbackReason != nil)
    }

    @Test("File result uses raw text when Off and model text when On")
    @MainActor
    func fileResultRespectsCleanupChoice() async throws {
        let parts = ["um  hello", "[noise]  world"]
        var cleaned: [String] = []
        let off = try await FileTranscriptPresenter.prepare(parts: parts, mode: .off, writingModelURL: nil) { part, _ in
            cleaned.append(part)
            return TextProcessingResult(raw: part, text: "changed", engine: "Qwen", styleID: "clean",
                                        corrections: [], cleanupSeconds: 0, fallbackReason: nil)
        }
        #expect(off.text == "um  hello [noise]  world")
        #expect(off.parts == parts)
        #expect(cleaned.isEmpty)

        let on = try await FileTranscriptPresenter.prepare(parts: parts, mode: .smart, writingModelURL: nil) { part, _ in
            cleaned.append(part)
            return TextProcessingResult(raw: part, text: part == parts[0] ? "Hello" : "world.",
                                        engine: "Qwen", styleID: "clean", corrections: [],
                                        cleanupSeconds: 0, fallbackReason: nil)
        }
        #expect(cleaned == parts)
        #expect(on.text == "Hello world.")
        #expect(on.parts == ["Hello", "world."])
        #expect(on.raw == "um  hello [noise]  world")
        #expect(on.cleanupEngine == "Qwen")

        let failed = try await FileTranscriptPresenter.prepare(parts: parts, mode: .smart, writingModelURL: nil) { part, _ in
            TextProcessingResult(raw: part, text: "partial", engine: part == parts[0] ? "Qwen" : "Rules fallback",
                                 styleID: "clean", corrections: [], cleanupSeconds: 0,
                                 fallbackReason: part == parts[0] ? nil : "Model unavailable")
        }
        #expect(failed.text == failed.raw)
        #expect(failed.cleanupEngine == nil)
        #expect(failed.cleanupWarning == "Model unavailable")
    }

    @Test("Whisper catalog contains verified models with exact labels and real variants")
    func whisperCatalogSpecs() {
        let largeV3 = WhisperModelsCatalog.spec(for: "whisper-large-v3")
        #expect(largeV3 != nil)
        #expect(largeV3?.name == "Whisper Large v3")
        #expect(largeV3?.label == "Maximum Accuracy")
        #expect(largeV3?.variant == "openai_whisper-large-v3")

        let turbo = WhisperModelsCatalog.spec(for: "whisper-large-v3-turbo")
        #expect(turbo != nil)
        #expect(turbo?.name == "Whisper Large v3 Turbo")
        #expect(turbo?.label == "Fast + Accurate")
        #expect(turbo?.variant == "openai_whisper-large-v3_turbo")

        let medium = WhisperModelsCatalog.spec(for: "whisper-medium")
        #expect(medium != nil)
        #expect(medium?.name == "Whisper Medium")
        #expect(medium?.label == "Balanced")
        #expect(medium?.variant == "openai_whisper-medium")

        let small = WhisperModelsCatalog.spec(for: "whisper-small")
        #expect(small != nil)
        #expect(small?.name == "Whisper Small")
        #expect(small?.label == "Lightweight")
        #expect(small?.variant == "openai_whisper-small")
    }

    @Test("Global dictation and File Transcription preferences remain strictly separate")
    @MainActor
    func preferenceSeparation() {
        let settings = Settings.shared
        let previousRomanScript = settings.fileTranscriptionRomanScript
        defer { settings.fileTranscriptionRomanScript = previousRomanScript }

        // Set global dictation
        settings.engine = .parakeet
        settings.selectedModelID = "parakeet-v3"

        // Set file transcription
        settings.fileTranscriptionModelID = "whisper-large-v3"
        settings.fileTranscriptionLanguage = "en"
        settings.fileTranscriptionCleanup = .smart
        settings.fileTranscriptionRomanScript = true

        // Verify changing file transcription does NOT mutate global dictation
        #expect(settings.selectedModelID == "parakeet-v3")
        #expect(settings.engine == .parakeet)
        #expect(settings.fileTranscriptionModelID == "whisper-large-v3")

        // Change global dictation
        settings.selectedModelID = "apple-speech"
        settings.engine = .apple

        // Verify file transcription was untouched
        #expect(settings.fileTranscriptionModelID == "whisper-large-v3")
        #expect(settings.fileTranscriptionLanguage == "en")
        #expect(settings.fileTranscriptionCleanup == .smart)
        #expect(settings.fileTranscriptionRomanScript)
    }

    @Test("FileTranscriptionJob snapshots parameters at initiation time")
    func jobSnapshotting() {
        let testURL = URL(fileURLWithPath: "/tmp/sample-audio.wav")
        let job = FileTranscriptionJob(
            fileURL: testURL,
            fileDuration: 42.5,
            modelID: "whisper-large-v3",
            modelDisplayName: "Whisper Large v3",
            modelVersion: "openai_whisper-large-v3",
            language: "auto",
            cleanupMode: .smart,
            romanScript: true
        )

        #expect(job.fileName == "sample-audio.wav")
        #expect(job.fileDuration == 42.5)
        #expect(job.modelID == "whisper-large-v3")
        #expect(job.modelDisplayName == "Whisper Large v3")
        #expect(job.modelVersion == "openai_whisper-large-v3")
        #expect(job.language == "auto")
        #expect(job.cleanupMode == .smart)
        #expect(job.romanScript)
    }

    @Test("WhisperKitPool model usage tracking and directory resolution")
    func whisperKitPoolDirectoryResolution() async {
        let largeV3Dir = WhisperKitPool.resolvedDirectory(for: "whisper-large-v3")
        #expect(largeV3Dir.path.contains("openai_whisper-large-v3"))

        let turboDir = WhisperKitPool.resolvedDirectory(for: "whisper-large-v3-turbo")
        #expect(turboDir.path.contains("openai_whisper-large-v3_turbo"))

        let inUse = await WhisperKitPool.shared.isModelInUse("whisper-large-v3")
        #expect(inUse == false)
    }
}
