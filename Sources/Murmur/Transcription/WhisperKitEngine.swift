import AVFoundation
import Foundation
import WhisperKit
import CoreML
import FluidAudio

extension WhisperKit: @retroactive @unchecked Sendable {}

/// Supported Whisper model definitions for Murmur.
public struct WhisperModelSpec: Sendable {
    public let id: String
    public let name: String
    public let label: String
    public let variant: String
    public let downloadSize: String
    public let diskSize: String
    public let attribution: String
}

public enum WhisperModelsCatalog {
    public static let largeV3 = WhisperModelSpec(
        id: "whisper-large-v3",
        name: "Whisper Large v3",
        label: "Maximum Accuracy",
        variant: "openai_whisper-large-v3",
        downloadSize: "~1.9 GB",
        diskSize: "~2.1 GB",
        attribution: "OpenAI Whisper Large v3 via WhisperKit CoreML. Full decoder architecture for maximum transcription fidelity."
    )

    public static let largeV3Turbo = WhisperModelSpec(
        id: "whisper-large-v3-turbo",
        name: "Whisper Large v3 Turbo",
        label: "Fast + Accurate",
        variant: "openai_whisper-large-v3_turbo",
        downloadSize: "~950 MB",
        diskSize: "~1.0 GB",
        attribution: "OpenAI Whisper Large v3 Turbo via WhisperKit CoreML. Pruned 4-layer decoder for higher speed."
    )

    public static let medium = WhisperModelSpec(
        id: "whisper-medium",
        name: "Whisper Medium",
        label: "Balanced",
        variant: "openai_whisper-medium",
        downloadSize: "~900 MB",
        diskSize: "~950 MB",
        attribution: "OpenAI Whisper Medium via WhisperKit CoreML."
    )

    public static let small = WhisperModelSpec(
        id: "whisper-small",
        name: "Whisper Small",
        label: "Lightweight",
        variant: "openai_whisper-small",
        downloadSize: "~290 MB",
        diskSize: "~310 MB",
        attribution: "OpenAI Whisper Small via WhisperKit CoreML. Lightweight profile."
    )

    public static let all: [WhisperModelSpec] = [largeV3, largeV3Turbo, medium, small]

    public static func spec(for id: String) -> WhisperModelSpec? {
        all.first { $0.id == id }
    }

    public static func specForVariant(_ variant: String) -> WhisperModelSpec? {
        all.first { $0.variant == variant }
    }
}

/// Actor managing the active WhisperKit instance, model lifetime, memory limits, and concurrent job leases.
public actor WhisperKitPool {
    public static let shared = WhisperKitPool()

    /// Base download and storage directory for Murmur Whisper models.
    public static let downloadBase: URL = {
        let appSupport = MurmurStorage.directory
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    private var activeKit: WhisperKit?
    private var activeModelID: String?
    private var activeLeases: [String: Int] = [:]
    private var idleTimerTask: Task<Void, Never>?

    private init() {}

    /// Checks if a model currently has active transcription jobs running.
    public func isModelInUse(_ modelID: String) -> Bool {
        (activeLeases[modelID] ?? 0) > 0
    }

    /// Resolves the on-disk directory for a given model ID.
    public static func resolvedDirectory(for modelID: String) -> URL {
        guard let spec = WhisperModelsCatalog.spec(for: modelID) else {
            return downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelID)")
        }

        // Primary location in Murmur Application Support
        let primary = downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(spec.variant)")
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }

        // Standard Hugging Face Documents cache fallback
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let hfDocs = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(spec.variant)")
            if FileManager.default.fileExists(atPath: hfDocs.path) {
                return hfDocs
            }
        }

        // User cache directory fallback
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let hfCaches = caches.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(spec.variant)")
            if FileManager.default.fileExists(atPath: hfCaches.path) {
                return hfCaches
            }
        }

        return primary
    }

    /// Checks if a Whisper model is completely downloaded and ready on disk.
    public static func isModelCompleteOnDisk(modelID: String) -> Bool {
        let dir = resolvedDirectory(for: modelID)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }

        // Must contain encoder, mel, and decoder
        let fm = FileManager.default
        let hasEncoder = fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlmodelc").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlpackage").path)
        let hasMel = fm.fileExists(atPath: dir.appendingPathComponent("MelSpectrogram.mlmodelc").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("MelSpectrogram.mlpackage").path)
        let hasDecoder = fm.fileExists(atPath: dir.appendingPathComponent("TextDecoder.mlmodelc").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("TextDecoderContextPrefill.mlmodelc").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("TextDecoder.mlpackage").path)

        return hasEncoder && hasMel && hasDecoder
    }

    /// Acquires a model instance for a transcription job.
    /// Ensures only ONE Whisper model variant is in memory at a time.
    private func acquire(modelID: String) async throws -> WhisperKit {
        idleTimerTask?.cancel()
        idleTimerTask = nil

        // If the requested model is already loaded in memory, reuse it immediately
        if let kit = activeKit, activeModelID == modelID {
            activeLeases[modelID, default: 0] += 1
            return kit
        }

        // If another model is loaded and in active use, we must wait or refuse concurrent conflict
        if let loaded = activeModelID, loaded != modelID {
            if (activeLeases[loaded] ?? 0) > 0 {
                throw NSError(
                    domain: "Murmur",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Model '\(loaded)' is currently processing another transcription job. Please wait for it to complete."]
                )
            }
            // Safely unload previous model before loading new one to preserve RAM
            Log.speech.info("WhisperKitPool: Unloading '\(loaded)' to free memory before loading '\(modelID)'.")
            activeKit = nil
            activeModelID = nil
        }

        guard Self.isModelCompleteOnDisk(modelID: modelID) else {
            throw NSError(
                domain: "Murmur",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Model '\(modelID)' is not installed. Download it from Voice Models first."]
            )
        }

        let modelDir = Self.resolvedDirectory(for: modelID)
        Log.speech.info("WhisperKitPool: Loading '\(modelID)' from \(modelDir.path)...")

        let kit = try await WhisperKit(
            modelFolder: modelDir.path,
            download: false
        )

        self.activeKit = kit
        self.activeModelID = modelID
        self.activeLeases[modelID, default: 0] += 1
        Log.speech.info("WhisperKitPool: Successfully loaded '\(modelID)' into Neural Engine.")
        return kit
    }

    /// Releases a lease when a job finishes. If no jobs remain, initiates idle unload.
    private func release(modelID: String) {
        let current = activeLeases[modelID] ?? 1
        let newCount = max(0, current - 1)
        activeLeases[modelID] = newCount

        if newCount == 0 {
            // Schedule idle unload after 45 seconds to avoid repeated reload churn
            idleTimerTask?.cancel()
            idleTimerTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.unloadIfIdle(modelID: modelID)
            }
        }
    }

    public func prepare(modelID: String) async throws {
        _ = try await acquire(modelID: modelID)
        release(modelID: modelID)
    }

    static func decodingOptions(language: String?) -> DecodingOptions {
        let identifier = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selected = identifier == "auto" || identifier?.isEmpty == true ? nil
            : identifier?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        var options = DecodingOptions(verbose: false, detectLanguage: selected == nil)
        options.task = .transcribe
        options.language = selected
        return options
    }

    /// Transcribes audio samples with the specified model completely inside actor isolation.
    public func transcribe(
        modelID: String,
        samples: [Float],
        language: String? = nil
    ) async throws -> String {
        try await transcribeWithLanguage(modelID: modelID, samples: samples, language: language).text
    }

    func transcribeWithLanguage(
        modelID: String,
        samples: [Float],
        language: String? = nil,
        vocabulary: [String] = []
    ) async throws -> SpeechRecognitionResult {
        let kit = try await acquire(modelID: modelID)
        defer {
            release(modelID: modelID)
        }

        var options = Self.decodingOptions(language: language)
        if !vocabulary.isEmpty, let tokenizer = kit.tokenizer {
            // Whole terms only, with a small token budget; no aliases or snippets.
            var tokens: [Int] = []
            for phrase in vocabulary.prefix(40) {
                let encoded = tokenizer.encode(text: " " + phrase).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                guard tokens.count + encoded.count <= 128 else { break }
                tokens += encoded
            }
            if !tokens.isEmpty { options.promptTokens = tokens }
        }
        let segments = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = segments.first(where: { !$0.language.isEmpty })?.language
        return SpeechRecognitionResult(text: text, language: options.language ?? detectedLanguage)
    }

    /// Explicitly unloads a model if it has no active leases.
    public func unloadIfIdle(modelID: String) {
        guard activeModelID == modelID else { return }
        if (activeLeases[modelID] ?? 0) == 0 {
            Log.speech.info("WhisperKitPool: Releasing idle model '\(modelID)' from RAM.")
            activeKit = nil
            activeModelID = nil
        }
    }

    /// Immediately purge any loaded model from memory (used on quit or manual clear).
    public func purgeAll() {
        idleTimerTask?.cancel()
        idleTimerTask = nil
        activeKit = nil
        activeModelID = nil
        activeLeases.removeAll()
    }
}

/// Helper for reading, decoding, and resampling audio/video files to 16kHz mono Float32 samples.
public enum UniversalAudioLoader {
    /// Loads an audio or video file at `url`, extracts the audio track, and converts to 16,000 Hz mono Float32.
    public static func loadAudioSamples(from url: URL) throws -> (samples: [Float], duration: Double) {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let duration: Double
        if let audioFile = try? AVAudioFile(forReading: url) {
            duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } else {
            duration = Double(samples.count) / 16_000.0
        }

        return (samples, max(duration, Double(samples.count) / 16_000.0))
    }
}

/// Whisper starts decoding while speech is still arriving, using the same engine
/// selection and language as the final transcript.
actor WhisperKitEngine: CancellableTranscriptionEngine {
    private let stream: StreamingSpeechEngine
    init(modelID: String = "whisper-large-v3", language: String? = nil, previewEnabled: Bool = true, vocabulary: [String] = []) {
        stream = StreamingSpeechEngine(modelID: modelID, language: language, previewEnabled: previewEnabled, vocabulary: vocabulary)
    }
    func preferredInputFormat() async -> AVAudioFormat? { await stream.preferredInputFormat() }
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> { try await stream.start() }
    func feed(_ chunk: AudioChunk) async { await stream.feed(chunk) }
    func finish() async { await stream.finish() }
    func cancel() async { await stream.cancel() }
}
