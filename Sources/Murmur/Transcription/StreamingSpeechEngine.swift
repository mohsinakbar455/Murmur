import AVFoundation
import FluidAudio
import Foundation

/// The window closes on a pause, retaining every sample exactly once. A hard bound
/// also limits memory/compute during uninterrupted speech. Preview never commits text.
struct SpeechWindowBuffer: Sendable {
    static let sampleRate = 16_000
    private(set) var samples: [Float] = []
    private(set) var silenceSamples = 0
    private(set) var lastVoiceSample = 0

    mutating func append(_ values: [Float]) {
        samples.append(contentsOf: values)
        for value in values {
            if abs(value) > 0.008 { silenceSamples = 0 }
            else { silenceSamples += 1 }
        }
        lastVoiceSample = samples.count - silenceSamples
    }

    var shouldCommit: Bool {
        samples.count >= 16_000 * 12 || (samples.count >= 16_000 * 2 && silenceSamples >= 8_000)
    }
    var hasSpeech: Bool { lastVoiceSample > 0 }

    mutating func removePrefix(_ count: Int) {
        samples.removeFirst(min(count, samples.count))
        silenceSamples = min(silenceSamples, samples.count)
        lastVoiceSample = max(0, samples.count - silenceSamples)
    }
}

/// Engines with this capability discard pending work instead of decoding a final tail.
protocol CancellableTranscriptionEngine: TranscriptionEngine {
    func cancel() async
}

/// Incremental recognition shared by batch speech backends. Each committed window
/// owns a disjoint sample range; preview text is replaced, never appended twice.
actor StreamingSpeechEngine: CancellableTranscriptionEngine {
    typealias Prepare = @Sendable () async throws -> Void
    typealias Recognize = @Sendable ([Float]) async throws -> String
    private static let windowLimit = 16_000 * 12
    private static let backlogLimit = 16_000 * 120

    private let prepare: Prepare
    private let recognize: Recognize
    private let previewEnabled: Bool
    private let pollInterval: Duration
    private var sessionID: UUID?
    private var window = SpeechWindowBuffer()
    private var committed: [String] = []
    private var preview = ""
    private var decodedCount = 0
    private var decodedVoicePosition = 0
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private var worker: Task<Void, Never>?
    private var inference: Task<String, Error>?
    private var finishTask: Task<Void, Never>?
    private var finishing = false
    private let converter = AudioConverter()

    init(
        modelID: String, language: String? = nil, previewEnabled: Bool = true, vocabulary: [String] = [],
        prepare: Prepare? = nil, recognize: Recognize? = nil,
        pollInterval: Duration? = nil
    ) {
        self.previewEnabled = previewEnabled
        self.prepare = prepare ?? { try await SpeechRecognitionService.shared.prepare(modelID: modelID) }
        self.recognize = recognize ?? {
            try await SpeechRecognitionService.shared.transcribe(samples: $0, modelID: modelID, language: language, vocabulary: vocabulary)
        }
        self.pollInterval = pollInterval ?? .milliseconds(modelID.hasPrefix("whisper") ? 1_500 : 450)
    }

    func preferredInputFormat() async -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard sessionID == nil else { throw TranscriptionError.notRunning }
        let id = UUID()
        sessionID = id
        finishing = false
        do {
            try await prepare()
            try Task.checkCancellation()
            guard sessionID == id else { throw CancellationError() }
        } catch {
            terminate(id: id, error: error)
            throw error
        }
        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation
        let interval = pollInterval
        worker = Task { [weak self] in
            while !Task.isCancelled {
                // Do not retain the actor across the timer's sleep.
                guard await self?.tick(id: id) == true else { return }
                do { try await Task.sleep(for: interval) }
                catch { return }
            }
        }
        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        guard let id = sessionID, !finishing else { return }
        do { appendSamples(try converter.resampleBuffer(chunk.buffer), id: id) }
        catch { terminate(id: id, error: error) }
    }

    /// The same input boundary used by capture, without an audio device in tests.
    func feedSamples(_ samples: [Float]) {
        guard let id = sessionID, !finishing else { return }
        appendSamples(samples, id: id)
    }

    private func appendSamples(_ samples: [Float], id: UUID) {
        guard samples.count <= Self.backlogLimit - window.samples.count else {
            terminate(id: id, error: TranscriptionError.modelInstallFailed(
                "Speech processing fell behind. Stop this recording and choose a faster model."
            ))
            return
        }
        window.append(samples)
    }

    private func tick(id: UUID) async -> Bool {
        guard sessionID == id, !finishing else { return false }
        guard window.samples.count >= 12_800,
              window.shouldCommit || (previewEnabled && window.samples.count - decodedCount >= 6_400) else { return true }
        do { try await decode(commit: window.shouldCommit, id: id) }
        catch { terminate(id: id, error: error); return false }
        return sessionID == id && !finishing
    }

    private func decode(commit: Bool, id: UUID) async throws {
        guard sessionID == id else { throw CancellationError() }
        let count = min(window.samples.count, Self.windowLimit)
        guard count > 0 else { return }
        var snapshot = Array(window.samples.prefix(count))
        let voice = snapshot.lastIndex(where: { abs($0) > 0.008 }).map { $0 + 1 } ?? 0
        var text = preview
        // Silence added after a preview does not require another recognition pass.
        if voice > 0 && (decodedCount == 0 || voice > decodedVoicePosition) {
            // Preserve even a very short voiced tail; batch backends require 100ms.
            if snapshot.count < 1_600 { snapshot += Array(repeating: 0, count: 1_600 - snapshot.count) }
            let recognize = self.recognize
            let task = Task { try await recognize(snapshot) }
            inference = task
            text = try await task.value
            guard sessionID == id else { throw CancellationError() }
            inference = nil
        }
        guard sessionID == id else { throw CancellationError() }
        if commit {
            if !text.isEmpty { committed.append(text) }
            // Samples captured during inference belong to the next window.
            window.removePrefix(count)
            preview = ""
            decodedCount = 0
            decodedVoicePosition = 0
        } else {
            preview = text
            decodedCount = count
            decodedVoicePosition = voice
        }
        continuation?.yield(TranscriptionChunk(text: fullText, isFinal: false))
    }

    private var fullText: String { (committed + [preview]).filter { !$0.isEmpty }.joined(separator: " ") }

    func finish() async {
        if let finishTask { await finishTask.value; return }
        guard let id = sessionID else { return }
        finishing = true
        let pending = worker
        worker = nil
        pending?.cancel()
        // A normal release waits for the preview already in flight and reuses it.
        // Cancellation instead invalidates the session and cancels inference.
        let task = Task { [weak self] in
            await pending?.value
            await self?.finishWindows(id: id)
        }
        finishTask = task
        await task.value
    }

    private func finishWindows(id: UUID) async {
        guard sessionID == id else { return }
        do {
            while !window.samples.isEmpty { try await decode(commit: true, id: id) }
            guard sessionID == id else { return }
            continuation?.yield(TranscriptionChunk(text: fullText, isFinal: true))
            continuation?.finish()
            clearSession()
        } catch { terminate(id: id, error: error) }
    }

    func cancel() async {
        guard let id = sessionID else { return }
        terminate(id: id, error: CancellationError())
    }

    private func terminate(id: UUID, error: Error) {
        guard sessionID == id else { return }
        worker?.cancel()
        inference?.cancel()
        finishTask?.cancel()
        continuation?.finish(throwing: error)
        clearSession()
    }

    private func clearSession() {
        sessionID = nil
        continuation = nil
        worker = nil
        inference = nil
        finishTask = nil
        finishing = false
        window = SpeechWindowBuffer()
        committed = []
        preview = ""
        decodedCount = 0
        decodedVoicePosition = 0
    }
}
