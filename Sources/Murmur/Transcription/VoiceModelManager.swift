import Foundation
import Observation
import FluidAudio
import WhisperKit
import SwiftUI
import AppKit

/// Lifecycle status of a speech recognition model.
public enum ModelStatus: Equatable, Sendable {
    case notInstalled
    case downloading(fraction: Double, phase: String)
    case verifying
    case installed
    case loading
    case active
    case error(String)

    public var isInstalled: Bool {
        switch self {
        case .installed, .loading, .active: return true
        default: return false
        }
    }

    public var badgeStatus: StatusBadge.Status {
        switch self {
        case .active, .installed: return .ready
        case .loading: return .loading
        case .downloading, .verifying: return .downloading
        case .notInstalled: return .idle
        case .error: return .error
        }
    }

    public var displayText: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .downloading(let fraction, let phase):
            return String(format: "%@ (%.0f%%)", phase, fraction * 100)
        case .verifying: return "Verifying…"
        case .installed: return "Installed"
        case .loading: return "Loading into Neural Engine…"
        case .active: return "Active"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Metadata describing a speech model in the Murmur catalog.
public struct VoiceModelDescriptor: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let runtime: String
    public let variant: String
    /// A short, user-facing reason to choose this model.
    public let summary: String
    /// One compact capability shown in the catalog's scanning view.
    public let compactCapability: String
    /// Relative catalog profile used to compare models. These are selection aids,
    /// not benchmark measurements or literal recognition rates.
    public let speedProfile: Int
    public let accuracyProfile: Int
    public let languages: [String]
    public let isStreaming: Bool
    public let downloadSize: String
    public let diskSize: String
    public var localURL: URL?
    public var status: ModelStatus
    public let attribution: String

    public var isApple: Bool { id == "apple-speech" }
    public var isWhisper: Bool { id.starts(with: "whisper") }
    public var isParakeet: Bool { id.starts(with: "parakeet") }
}

/// Actor-safe manager for model discovery, downloading, and activation.
@MainActor
@Observable
public final class VoiceModelManager {
    public static let shared = VoiceModelManager()

    public private(set) var models: [VoiceModelDescriptor] = []
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        buildCatalog()
        refreshModelStatuses()
    }

    /// The model currently verified and active for dictation.
    public var activeModelID: String {
        if Settings.shared.engine == .apple {
            return "apple-speech"
        }
        let chosen = Settings.shared.selectedModelID
        if isModelInstalled(id: chosen) {
            return chosen
        }
        // A missing selected model is not an active Apple Speech engine.
        return ""
    }

    /// Checks if a model's assets are verified on disk.
    public func isModelInstalled(id: String) -> Bool {
        if id == "apple-speech" { return true }
        if id.starts(with: "whisper") {
            return WhisperKitPool.isModelCompleteOnDisk(modelID: id)
        }
        let version: AsrModelVersion
        switch id {
        case "parakeet-v2": version = .v2
        case "parakeet-110m": version = .tdtCtc110m
        default: version = .v3
        }
        let cacheDir = Self.resolvedDirectory(for: version)
        return Self.isModelCompleteOnDisk(at: cacheDir, version: version)
    }

    /// Builds the catalog of supported models.
    private func buildCatalog() {
        models = [
            // Whisper Models
            VoiceModelDescriptor(
                id: "whisper-large-v3",
                name: "Whisper Large v3",
                provider: "OpenAI",
                runtime: "WhisperKit Core ML",
                variant: "Maximum Accuracy",
                summary: "Maximum accuracy",
                compactCapability: "99 languages",
                speedProfile: 55,
                accuracyProfile: 98,
                languages: ["99 Languages (Multilingual)"],
                isStreaming: true,
                downloadSize: "~1.9 GB",
                diskSize: "~2.1 GB",
                localURL: WhisperKitPool.resolvedDirectory(for: "whisper-large-v3"),
                status: .notInstalled,
                attribution: "OpenAI Whisper Large v3 via WhisperKit CoreML. Full decoder architecture for maximum transcription fidelity."
            ),
            VoiceModelDescriptor(
                id: "whisper-large-v3-turbo",
                name: "Whisper Large v3 Turbo",
                provider: "OpenAI",
                runtime: "WhisperKit Core ML",
                variant: "Fast + Accurate",
                summary: "Fast + accurate",
                compactCapability: "99 languages",
                speedProfile: 85,
                accuracyProfile: 95,
                languages: ["99 Languages (Multilingual)"],
                isStreaming: true,
                downloadSize: "~950 MB",
                diskSize: "~1.0 GB",
                localURL: WhisperKitPool.resolvedDirectory(for: "whisper-large-v3-turbo"),
                status: .notInstalled,
                attribution: "OpenAI Whisper Large v3 Turbo via WhisperKit CoreML. Pruned 4-layer decoder for higher speed."
            ),
            VoiceModelDescriptor(
                id: "whisper-medium",
                name: "Whisper Medium",
                provider: "OpenAI",
                runtime: "WhisperKit Core ML",
                variant: "Balanced",
                summary: "Balanced",
                compactCapability: "99 languages",
                speedProfile: 75,
                accuracyProfile: 90,
                languages: ["99 Languages (Multilingual)"],
                isStreaming: true,
                downloadSize: "~900 MB",
                diskSize: "~950 MB",
                localURL: WhisperKitPool.resolvedDirectory(for: "whisper-medium"),
                status: .notInstalled,
                attribution: "OpenAI Whisper Medium via WhisperKit CoreML."
            ),
            VoiceModelDescriptor(
                id: "whisper-small",
                name: "Whisper Small",
                provider: "OpenAI",
                runtime: "WhisperKit Core ML",
                variant: "Lightweight",
                summary: "Lightweight",
                compactCapability: "99 languages",
                speedProfile: 95,
                accuracyProfile: 82,
                languages: ["99 Languages (Multilingual)"],
                isStreaming: true,
                downloadSize: "~290 MB",
                diskSize: "~310 MB",
                localURL: WhisperKitPool.resolvedDirectory(for: "whisper-small"),
                status: .notInstalled,
                attribution: "OpenAI Whisper Small via WhisperKit CoreML. Lightweight profile."
            ),

            // Parakeet Models
            VoiceModelDescriptor(
                id: "parakeet-v3",
                name: "Parakeet TDT v3",
                provider: "NVIDIA",
                runtime: "FluidAudio Core ML",
                variant: "Very Fast",
                summary: "Very fast",
                compactCapability: "25 languages",
                speedProfile: 96,
                accuracyProfile: 94,
                languages: ["25 European Languages (es, fr, de, it, etc.)"],
                isStreaming: true,
                downloadSize: "~620 MB",
                diskSize: "~670 MB",
                localURL: AsrModels.defaultCacheDirectory(for: .v3),
                status: .notInstalled,
                attribution: "NVIDIA FastConformer-TDT v3 multilingual via FluidAudio CoreML."
            ),
            VoiceModelDescriptor(
                id: "parakeet-v2",
                name: "Parakeet TDT v2",
                provider: "NVIDIA",
                runtime: "FluidAudio Core ML",
                variant: "English",
                summary: "English transcription",
                compactCapability: "English",
                speedProfile: 95,
                accuracyProfile: 91,
                languages: ["English (en)"],
                isStreaming: true,
                downloadSize: "~470 MB",
                diskSize: "~510 MB",
                localURL: AsrModels.defaultCacheDirectory(for: .v2),
                status: .notInstalled,
                attribution: "NVIDIA FastConformer-TDT via FluidAudio CoreML."
            ),
            VoiceModelDescriptor(
                id: "parakeet-110m",
                name: "Parakeet TDT-CTC 110M",
                provider: "NVIDIA",
                runtime: "FluidAudio Core ML",
                variant: "Compact Hybrid",
                summary: "Compact & fast",
                compactCapability: "English",
                speedProfile: 99,
                accuracyProfile: 83,
                languages: ["English (en)"],
                isStreaming: true,
                downloadSize: "~140 MB",
                diskSize: "~160 MB",
                localURL: AsrModels.defaultCacheDirectory(for: .tdtCtc110m),
                status: .notInstalled,
                attribution: "Lightweight 110M parameter hybrid ASR via FluidAudio."
            ),

            // Apple Speech
            VoiceModelDescriptor(
                id: "apple-speech",
                name: "Apple Speech",
                provider: "Apple",
                runtime: "SpeechTranscriber",
                variant: "Native",
                summary: "Native transcription",
                compactCapability: "System language",
                speedProfile: 100,
                accuracyProfile: 86,
                languages: ["System Language", "Multilingual (OS-managed)"],
                isStreaming: true,
                downloadSize: "System Managed",
                diskSize: "~500 MB (OS managed)",
                localURL: nil,
                status: .active,
                attribution: "Apple SpeechTranscriber framework on macOS."
            )
        ]
    }

    public static func resolvedDirectory(for version: AsrModelVersion) -> URL {
        let standard = AsrModels.defaultCacheDirectory(for: version)
        if FileManager.default.fileExists(atPath: standard.path) {
            return standard
        }
        let fallback = standard.deletingLastPathComponent().appendingPathComponent(version.modelFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return standard
    }

    /// Verifies complete model installation on disk.
    public static func isModelCompleteOnDisk(at cacheDir: URL, version: AsrModelVersion) -> Bool {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return false }
        let directModelPresent = FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("Decoder.mlmodelc").path)
            && FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("Preprocessor.mlmodelc").path)
        let exists = AsrModels.modelsExist(at: cacheDir, version: version, encoderPrecision: .int8)
            || AsrModels.modelsExist(at: cacheDir, version: version, encoderPrecision: .int4)
            || directModelPresent
        return exists
    }

    /// Refreshes the on-disk and active status of each model.
    public func refreshModelStatuses() {
        // Reconcile settings: if currently set to Parakeet or Whisper but uninstalled, reconcile safely.
        if Settings.shared.engine == .parakeet && !isModelInstalled(id: Settings.shared.selectedModelID) {
            Log.app.info("Reconciling engine: \(Settings.shared.selectedModelID) not on disk. Falling back to Apple Speech.")
            Settings.shared.engine = .apple
            Settings.shared.selectedModelID = "apple-speech"
        } else if Settings.shared.engine == .whisper && !isModelInstalled(id: Settings.shared.selectedModelID) {
            Log.app.info("Reconciling engine: \(Settings.shared.selectedModelID) not on disk. Falling back to Apple Speech.")
            Settings.shared.engine = .apple
            Settings.shared.selectedModelID = "apple-speech"
        }

        let currentActive = self.activeModelID

        for index in models.indices {
            let id = models[index].id

            if id == "apple-speech" {
                models[index].status = (currentActive == "apple-speech") ? .active : .installed
                continue
            }

            // Check if downloading
            if downloadTasks[id] != nil {
                continue
            }

            if id.starts(with: "whisper") {
                let exists = WhisperKitPool.isModelCompleteOnDisk(modelID: id)
                models[index].localURL = WhisperKitPool.resolvedDirectory(for: id)
                if exists {
                    models[index].status = (currentActive == id) ? .active : .installed
                } else {
                    models[index].status = .notInstalled
                }
                continue
            }

            let version: AsrModelVersion
            switch id {
            case "parakeet-v2": version = .v2
            case "parakeet-110m": version = .tdtCtc110m
            default: version = .v3
            }

            let cacheDir = Self.resolvedDirectory(for: version)
            let exists = Self.isModelCompleteOnDisk(at: cacheDir, version: version)
            models[index].localURL = cacheDir

            if exists {
                models[index].status = (currentActive == id) ? .active : .installed
            } else {
                models[index].status = .notInstalled
            }
        }
    }

    /// Triggers download for a given model.
    public func startDownload(for modelID: String) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        guard downloadTasks[modelID] == nil else { return }

        if modelID.starts(with: "whisper"), let spec = WhisperModelsCatalog.spec(for: modelID) {
            models[index].status = .downloading(fraction: 0.05, phase: "Starting Whisper download…")

            let task = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    _ = try await WhisperKit.download(
                        variant: spec.variant,
                        downloadBase: WhisperKitPool.downloadBase,
                        progressCallback: { progress in
                            Task { @MainActor in
                                guard let self else { return }
                                if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                                    self.models[idx].status = .downloading(
                                        fraction: progress.fractionCompleted,
                                        phase: "Downloading Whisper weights"
                                    )
                                }
                            }
                        }
                    )

                    await MainActor.run {
                        guard let self else { return }
                        self.downloadTasks.removeValue(forKey: modelID)
                        if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                            self.models[idx].status = .installed
                        }
                        // Once Whisper Large v3 has been downloaded:
                        // Default File Transcription model: Whisper Large v3
                        if modelID == "whisper-large-v3" {
                            Settings.shared.fileTranscriptionModelID = "whisper-large-v3"
                            Log.speech.info("Defaulted File Transcription model to Whisper Large v3.")
                        }
                        self.refreshModelStatuses()
                    }
                } catch {
                    await MainActor.run {
                        guard let self else { return }
                        self.downloadTasks.removeValue(forKey: modelID)
                        if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                            self.models[idx].status = .error(error.localizedDescription)
                        }
                    }
                }
            }
            downloadTasks[modelID] = task
            return
        }

        let version: AsrModelVersion
        switch modelID {
        case "parakeet-v2": version = .v2
        case "parakeet-110m": version = .tdtCtc110m
        default: version = .v3
        }

        models[index].status = .downloading(fraction: 0.05, phase: "Starting download…")

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                _ = try await AsrModels.download(
                    version: version,
                    encoderPrecision: .int8,
                    progressHandler: { progress in
                        Task { @MainActor in
                            guard let self else { return }
                            if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                                let phaseName: String
                                switch progress.phase {
                                case .listing: phaseName = "Checking repository"
                                case .downloading(let cur, let total): phaseName = "Downloading file \(cur)/\(total)"
                                case .compiling(let name): phaseName = "Compiling \(name)"
                                }
                                self.models[idx].status = .downloading(
                                    fraction: progress.fractionCompleted,
                                    phase: phaseName
                                )
                            }
                        }
                    }
                )

                await MainActor.run {
                    guard let self else { return }
                    self.downloadTasks.removeValue(forKey: modelID)
                    if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                        self.models[idx].status = .installed
                    }
                    self.refreshModelStatuses()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.downloadTasks.removeValue(forKey: modelID)
                    if let idx = self.models.firstIndex(where: { $0.id == modelID }) {
                        self.models[idx].status = .error(error.localizedDescription)
                    }
                }
            }
        }

        downloadTasks[modelID] = task
    }

    /// Cancels an in-flight download.
    public func cancelDownload(for modelID: String) {
        guard let task = downloadTasks[modelID] else { return }
        task.cancel()
        downloadTasks.removeValue(forKey: modelID)
        refreshModelStatuses()
    }

    /// Activates a model for use in dictation. Throws if uninstalled.
    public func activate(modelID: String) throws {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        if modelID != "apple-speech" && !isModelInstalled(id: modelID) {
            throw NSError(
                domain: "Murmur",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Cannot activate '\(models[index].name)' because it is not installed. Download it first."]
            )
        }

        Settings.shared.selectedModelID = modelID
        if modelID == "apple-speech" {
            Settings.shared.engine = .apple
        } else if modelID.starts(with: "whisper") {
            Settings.shared.engine = .whisper
        } else {
            Settings.shared.engine = .parakeet
        }

        refreshModelStatuses()
    }

    /// Removes an installed model from disk.
    public func remove(modelID: String) async throws {
        guard modelID != "apple-speech" else { return }
        guard modelID != activeModelID else {
            throw NSError(domain: "Murmur", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot remove currently active dictation model. Switch models first."])
        }

        if await WhisperKitPool.shared.isModelInUse(modelID) {
            throw NSError(domain: "Murmur", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot remove '\(modelID)' while it is in active use by a transcription job."])
        }

        if modelID.starts(with: "whisper") {
            let targetDir = WhisperKitPool.resolvedDirectory(for: modelID)
            if FileManager.default.fileExists(atPath: targetDir.path) {
                try FileManager.default.removeItem(at: targetDir)
            }
        } else {
            let version: AsrModelVersion
            switch modelID {
            case "parakeet-v2": version = .v2
            case "parakeet-110m": version = .tdtCtc110m
            default: version = .v3
            }

            let targetDir = Self.resolvedDirectory(for: version)
            if FileManager.default.fileExists(atPath: targetDir.path) {
                try FileManager.default.removeItem(at: targetDir)
            }
        }

        refreshModelStatuses()
    }

    /// Reveals model directory in Finder.
    public func revealInFinder(modelID: String) {
        guard let model = models.first(where: { $0.id == modelID }), let localURL = model.localURL else { return }
        if FileManager.default.fileExists(atPath: localURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([localURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([localURL.deletingLastPathComponent()])
        }
    }
}
