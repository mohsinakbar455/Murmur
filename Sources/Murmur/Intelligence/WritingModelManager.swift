import Foundation
import Observation
import CryptoKit
import AppKit

struct WritingModelDescriptor: Identifiable, Sendable {
    let id: String
    let name: String
    let shortSummary: String
    let summary: String
    let fileName: String
    let revision: String
    let expectedBytes: Int64
    let sha256: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/unsloth/Qwen3.5-\(id)-GGUF/resolve/\(revision)/\(fileName)")!
    }
    var downloadSize: String { ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file) }

    // Immutable revisions and LFS size/SHA-256 checked against Hugging Face's model API, 2026-09-27.
    static let catalog: [Self] = [
        .init(id: "2B", name: "Qwen · Light", shortSummary: "Everyday cleanup", summary: "A smaller download for everyday cleanup and Macs with less memory.",
              fileName: "Qwen3.5-2B-Q4_K_M.gguf", revision: "f6d5376be1edb4d416d56da11e5397a961aca8ae",
              expectedBytes: 1_280_835_840, sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"),
        .init(id: "4B", name: "Qwen · Balanced", shortSummary: "Writing & notes", summary: "Recommended starting point for cleanup, writing styles and meeting notes.",
              fileName: "Qwen3.5-4B-Q4_K_M.gguf", revision: "e87f176479d0855a907a41277aca2f8ee7a09523",
              expectedBytes: 2_740_937_888, sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"),
        .init(id: "9B", name: "Qwen · Detailed", shortSummary: "Advanced writing", summary: "More capable local writing. Uses more memory and takes longer to prepare.",
              fileName: "Qwen3.5-9B-Q4_K_M.gguf", revision: "3885219b6810b007914f3a7950a8d1b469d598a5",
              expectedBytes: 5_680_522_464, sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8")
    ]
}

enum WritingModelState: Equatable, Sendable {
    case notInstalled, paused, verifying, installed
    case downloading(Double)
    case error(String)

    var isInstalled: Bool { self == .installed }
}

/// All weights are opt-in. Bundled inference code is separate from downloaded model data.
@MainActor
@Observable
final class WritingModelManager {
    static let shared = WritingModelManager()
    let catalog: [WritingModelDescriptor]
    private(set) var selectedModelID: String?
    private(set) var states: [String: WritingModelState] = [:]
    private(set) var errorMessage: String?
    @ObservationIgnored private var transfers: [String: WritingDownloadOperation] = [:]
    @ObservationIgnored private var verificationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [String: UUID] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults

    var runtimeAvailable: Bool { LocalTextRuntime.runtimeAvailable }
    var selectedModelURL: URL? {
        guard let id = selectedModelID, state(for: id).isInstalled,
              let model = catalog.first(where: { $0.id == id }) else { return nil }
        let url = directory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// File cleanup can use any verified local model, even when dictation is set to Basic cleanup.
    var fileTranscriptionModelURL: URL? {
        if let selectedModelURL { return selectedModelURL }
        for model in catalog where state(for: model.id).isInstalled {
            let url = directory.appendingPathComponent(model.fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    init(directory: URL? = nil, defaults: UserDefaults = .standard,
         catalog: [WritingModelDescriptor] = WritingModelDescriptor.catalog) {
        self.catalog = catalog
        self.directory = directory ?? MurmurStorage.directory
            .appendingPathComponent("WritingModels", isDirectory: true)
        self.defaults = defaults
        selectedModelID = defaults.string(forKey: "writingModelID")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            for model in catalog {
                let url = self.directory.appendingPathComponent(model.fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    verify(model, file: url, isStaged: false)
                } else if let staged = try FileManager.default.contentsOfDirectory(
                    at: self.directory, includingPropertiesForKeys: nil
                ).first(where: {
                    $0.lastPathComponent.hasPrefix(model.fileName + ".") && $0.pathExtension == "partial"
                }) {
                    // A quit after the network finished but before hashing/activation must not redownload gigabytes.
                    verify(model, file: staged, isStaged: true)
                } else {
                    states[model.id] = FileManager.default.fileExists(atPath: resumeURL(model.id).path) ? .paused : .notInstalled
                }
            }
        } catch { errorMessage = "Writing models could not be opened: \(error.localizedDescription)" }
    }

    func state(for id: String) -> WritingModelState {
        let state = states[id] ?? .notInstalled
        guard state.isInstalled, let model = catalog.first(where: { $0.id == id }) else { return state }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(model.fileName).path)
            ? .installed : .notInstalled
    }

    func select(id: String) {
        guard state(for: id).isInstalled else { return }
        selectedModelID = id
        defaults.set(id, forKey: "writingModelID")
    }

    func download(id: String) {
        guard let model = catalog.first(where: { $0.id == id }), transfers[id] == nil,
              verificationTasks[id] == nil, !state(for: id).isInstalled else { return }
        do {
            let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            if let capacity, capacity < model.expectedBytes + 512_000_000 {
                states[id] = .error("Free at least \(model.downloadSize) plus 512 MB, then try again.")
                return
            }
        } catch {
            states[id] = .error("Could not check available storage: \(error.localizedDescription)")
            return
        }
        errorMessage = nil
        let generation = UUID()
        generations[id] = generation
        states[id] = .downloading(0)
        let staging = directory.appendingPathComponent("\(model.fileName).\(generation).partial")
        let resume = try? Data(contentsOf: resumeURL(id))
        let operation = WritingDownloadOperation(model: model, stagingURL: staging, resumeData: resume) { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.generations[id] == generation else { return }
                self.states[id] = .downloading(fraction)
            }
        } completion: { [weak self] file, resumeData, message in
            Task { @MainActor in
                guard let self, self.generations[id] == generation else {
                    if let file { try? FileManager.default.removeItem(at: file) }
                    return
                }
                self.transfers[id] = nil
                if let resumeData { try? resumeData.write(to: self.resumeURL(id), options: .atomic) }
                if let file {
                    try? FileManager.default.removeItem(at: self.resumeURL(id))
                    self.verify(model, file: file, isStaged: true)
                } else {
                    if resumeData == nil { try? FileManager.default.removeItem(at: self.resumeURL(id)) }
                    self.states[id] = .error(message ?? "Download interrupted. Try again.")
                }
            }
        }
        transfers[id] = operation
        operation.start()
    }

    /// Cancel the transfer while preserving URLSession's resumable bytes for the next Download action.
    func cancelDownload(id: String) {
        guard let operation = transfers.removeValue(forKey: id) else { return }
        let generation = UUID()
        generations[id] = generation
        states[id] = .paused
        let destination = resumeURL(id)
        operation.pause { [weak self] data in
            Task { @MainActor in
                guard let self, self.generations[id] == generation else { return }
                if let data { try? data.write(to: destination, options: .atomic) }
            }
        }
    }

    func remove(id: String) {
        guard let model = catalog.first(where: { $0.id == id }), transfers[id] == nil,
              verificationTasks[id] == nil else { return }
        do {
            let url = directory.appendingPathComponent(model.fileName)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try? FileManager.default.removeItem(at: resumeURL(id))
            states[id] = .notInstalled
            if selectedModelID == id {
                selectedModelID = nil
                defaults.removeObject(forKey: "writingModelID")
                Task { await LocalTextRuntime.shared.shutdown() }
            }
        } catch { errorMessage = "Could not delete \(model.name): \(error.localizedDescription)" }
    }

    func revealInFinder(id: String) {
        guard state(for: id).isInstalled,
              let model = catalog.first(where: { $0.id == id }) else { return }
        let url = directory.appendingPathComponent(model.fileName)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Await from applicationShouldTerminate before replying to AppKit's deferred termination.
    /// Persisting resume data here lets a normal quit continue multi-GB downloads next launch.
    func prepareForTermination() async {
        let pending = transfers
        transfers.removeAll()
        for (id, operation) in pending {
            generations[id] = UUID()
            states[id] = .paused
            let data: Data? = await withCheckedContinuation { continuation in
                operation.pause { data in continuation.resume(returning: data) }
            }
            if let data { try? data.write(to: resumeURL(id), options: .atomic) }
        }
    }

    private func resumeURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).resume") }

    private func verify(_ model: WritingModelDescriptor, file: URL, isStaged: Bool) {
        states[model.id] = .verifying
        verificationTasks[model.id] = Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try WritingModelIntegrity.validate(file, expectedBytes: model.expectedBytes, sha256: model.sha256)
                }.value
                guard let self else { return }
                if isStaged {
                    let destination = self.directory.appendingPathComponent(model.fileName)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: file)
                    } else { try FileManager.default.moveItem(at: file, to: destination) }
                }
                self.states[model.id] = .installed
                self.verificationTasks[model.id] = nil
                if self.selectedModelID == nil { self.select(id: model.id) }
            } catch {
                guard let self else { return }
                if isStaged { try? FileManager.default.removeItem(at: file) }
                self.states[model.id] = .error(error.localizedDescription)
                self.verificationTasks[model.id] = nil
            }
        }
    }
}

enum WritingModelIntegrity {
    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func validate(_ url: URL, expectedBytes: Int64, sha256: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == expectedBytes else {
            throw ValidationError(message: "The model download is incomplete. Download it again.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw ValidationError(message: "The download is not a GGUF model. Download it again.")
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256.lowercased() else {
            throw ValidationError(message: "The model did not pass its integrity check. Download it again.")
        }
    }
}

/// Delegate owns only immutable metadata. Mutable lifecycle/UI state remains on MainActor.
private final class WritingDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let model: WritingModelDescriptor
    let stagingURL: URL
    let progress: @Sendable (Double) -> Void
    let completion: @Sendable (URL?, Data?, String?) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask!

    init(model: WritingModelDescriptor, stagingURL: URL, resumeData: Data?,
         progress: @escaping @Sendable (Double) -> Void,
         completion: @escaping @Sendable (URL?, Data?, String?) -> Void) {
        self.model = model
        self.stagingURL = stagingURL
        self.progress = progress
        self.completion = completion
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 86_400
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        if let resumeData { task = session.downloadTask(withResumeData: resumeData) }
        else { task = session.downloadTask(with: model.downloadURL) }
    }

    func start() { task.resume() }
    func pause(_ callback: @escaping @Sendable (Data?) -> Void) { task.cancel(byProducingResumeData: callback) }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(min(1, Double(totalBytesWritten) / Double(model.expectedBytes)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            completion(nil, nil, "The model server could not provide the download. Try again later.")
            return
        }
        do {
            // URLSession deletes its temporary file immediately after this delegate returns.
            try FileManager.default.moveItem(at: location, to: stagingURL)
            completion(stagingURL, nil, nil)
        } catch { completion(nil, nil, "Could not save the model: \(error.localizedDescription)") }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        guard let error else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        completion(nil, resume, "Download interrupted: \(error.localizedDescription)")
    }
}
