import AVFoundation
import FluidAudio
import Foundation
import Speech

struct SpeechRecognitionResult: Sendable {
    let text: String
    let language: String?
}

/// One owner serializes speech inference across dictation, files and meetings.
/// Actor isolation alone is insufficient: model calls suspend and allow reentrancy.
actor SpeechRecognitionService {
    static let shared = SpeechRecognitionService()
    private var occupied = false
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []

    static func parakeetVersion(for modelID: String) -> AsrModelVersion {
        switch modelID {
        case "parakeet-v2": .v2
        case "parakeet-110m": .tdtCtc110m
        default: .v3
        }
    }

    private func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if !occupied { occupied = true; return }
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty { occupied = false }
        else { waiters.removeFirst().continuation.resume() }
    }

    func prepare(modelID: String) async throws {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        if modelID.hasPrefix("parakeet") {
            let version = Self.parakeetVersion(for: modelID)
            guard ParakeetModels.isVersionDownloaded(version) else {
                throw TranscriptionError.modelInstallFailed("Download this speech model from Models first.")
            }
            _ = try await ParakeetModels.shared.manager(for: version)
        } else if modelID.hasPrefix("whisper") {
            try await WhisperKitPool.shared.prepare(modelID: modelID)
        }
        try Task.checkCancellation()
    }

    func transcribe(samples: [Float], modelID: String, language: String? = nil, vocabulary: [String] = []) async throws -> String {
        try await transcribeWithLanguage(samples: samples, modelID: modelID, language: language, vocabulary: vocabulary).text
    }

    func transcribeWithLanguage(samples: [Float], modelID: String, language: String? = nil, vocabulary: [String] = []) async throws -> SpeechRecognitionResult {
        guard samples.count >= 1_600 else { return SpeechRecognitionResult(text: "", language: language) }
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        let result: SpeechRecognitionResult
        if modelID.hasPrefix("parakeet") {
            let version = Self.parakeetVersion(for: modelID)
            guard ParakeetModels.isVersionDownloaded(version) else {
                throw TranscriptionError.modelInstallFailed("Download this speech model from Models first.")
            }
            let manager = try await ParakeetModels.shared.manager(for: version)
            var state = try TdtDecoderState()
            result = SpeechRecognitionResult(text: try await manager.transcribe(samples, decoderState: &state).text, language: language)
        } else if modelID.hasPrefix("whisper") {
            result = try await WhisperKitPool.shared.transcribeWithLanguage(
                modelID: modelID, samples: samples, language: language, vocabulary: vocabulary
            )
        } else if modelID == "apple-speech" {
            result = SpeechRecognitionResult(text: try await transcribeWithApple(samples: samples, language: language), language: language)
        } else {
            throw TranscriptionError.modelInstallFailed("Unknown speech model. Choose a model in Models.")
        }
        try Task.checkCancellation()
        return SpeechRecognitionResult(text: result.text.trimmingCharacters(in: .whitespacesAndNewlines), language: result.language)
    }

    private func transcribeWithApple(samples: [Float], language: String?) async throws -> String {
        let locale = language.flatMap { $0 == "auto" ? nil : Locale(identifier: $0) } ?? .current
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeUnsupported(locale)
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: file) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriptionError.noAudioFormat
        }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        do {
            let writer = try AVAudioFile(forWriting: file, settings: format.settings)
            try writer.write(from: buffer)
        }
        let collector = Task { () throws -> String in
            var text = ""
            for try await item in transcriber.results where item.isFinal { text += String(item.text.characters) }
            return text
        }
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let input = try AVAudioFile(forReading: file)
                try await analyzer.start(inputAudioFile: input, finishAfterFile: true)
                let result = try await collector.value
                try Task.checkCancellation()
                return result
            } onCancel: {
                collector.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
