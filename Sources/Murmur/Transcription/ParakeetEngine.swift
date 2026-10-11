import AVFoundation
import FluidAudio
import Foundation

extension AsrModelVersion {
    var modelFolderName: String {
        switch self {
        case .v2: return "parakeet-tdt-0.6b-v2-coreml"
        case .v3: return "parakeet-tdt-0.6b-v3"
        case .tdtCtc110m: return "parakeet-tdt-ctc-110m"
        case .tdtJa: return "parakeet-tdt-ja"
        }
    }
}

/// Parakeet uses the shared incremental pipeline; model selection remains unchanged.
actor ParakeetEngine: CancellableTranscriptionEngine {
    private let stream: StreamingSpeechEngine
    init(version: AsrModelVersion = .v3, precision: ParakeetEncoderPrecision = .int8,
         previewEnabled: Bool = true) {
        let modelID: String
        switch version {
        case .v2: modelID = "parakeet-v2"
        case .tdtCtc110m: modelID = "parakeet-110m"
        default: modelID = "parakeet-v3"
        }
        stream = StreamingSpeechEngine(modelID: modelID, previewEnabled: previewEnabled)
    }
    func preferredInputFormat() async -> AVAudioFormat? { await stream.preferredInputFormat() }
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> { try await stream.start() }
    func feed(_ chunk: AudioChunk) async { await stream.feed(chunk) }
    func finish() async { await stream.finish() }
    func cancel() async { await stream.cancel() }
}

/// Process-wide version-aware model cache for Neural Engine models.
actor ParakeetModels {
    static let shared = ParakeetModels()

    /// Checks if a specific version is downloaded on disk.
    nonisolated static func isVersionDownloaded(
        _ version: AsrModelVersion,
        precision: ParakeetEncoderPrecision = .int8
    ) -> Bool {
        let cacheDir = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: cacheDir, version: version, encoderPrecision: precision)
    }

    /// True if any supported Parakeet model is downloaded.
    nonisolated static var isDownloaded: Bool {
        isVersionDownloaded(.v3) || isVersionDownloaded(.v2) || isVersionDownloaded(.tdtCtc110m)
    }

    private var loadedManagers: [String: AsrManager] = [:]
    private var activeLoadTasks: [String: Task<AsrManager, Error>] = [:]

    func isLoaded(for version: AsrModelVersion) -> Bool {
        loadedManagers.keys.contains { $0.hasPrefix(version.modelFolderName + "-") }
    }

    /// Loads model variant once; concurrent callers await the same in-flight task.
    func manager(
        for version: AsrModelVersion = .v3,
        precision: ParakeetEncoderPrecision = .int8
    ) async throws -> AsrManager {
        let key = "\(version.modelFolderName)-\(precision.rawValue)"

        if let existing = loadedManagers[key] {
            return existing
        }

        if let inFlight = activeLoadTasks[key] {
            return try await inFlight.value
        }

        let task = Task<AsrManager, Error> {
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            let isCached = AsrModels.modelsExist(at: cacheDir, version: version, encoderPrecision: precision)

            let stage = isCached
                ? "loading \(version.modelFolderName) from disk"
                : "downloading \(version.modelFolderName) (~500 MB, one time)"
            Log.speech.info("Parakeet: \(stage, privacy: .public)")

            let started = Date()
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                encoderPrecision: precision
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            Log.speech.info("Parakeet (\(key)): ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return manager
        }

        activeLoadTasks[key] = task

        do {
            let manager = try await task.value
            loadedManagers[key] = manager
            activeLoadTasks.removeValue(forKey: key)
            return manager
        } catch {
            activeLoadTasks.removeValue(forKey: key)
            throw error
        }
    }
}
