import MurmurDictionary
import AVFoundation
import AppKit
import FluidAudio
import Foundation
import Observation
import os

/// Builds the engine named by the current setting.
///
/// Read settings for each utterance so model changes apply on the next recording.
@MainActor
func engineForCurrentSetting() -> any TranscriptionEngine {
    let settings = Settings.shared
    let vocabulary = LearnedTermStore.shared.vocabulary(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    switch settings.engine {
    case .apple:
        return AppleSpeechEngine(locale: settings.selectedLanguage == "auto" ? .current : Locale(identifier: settings.selectedLanguage), vocabulary: vocabulary)
    case .parakeet:
        return ParakeetEngine(version: SpeechRecognitionService.parakeetVersion(for: settings.selectedModelID), previewEnabled: settings.livePreview)
    case .whisper:
        return WhisperKitEngine(modelID: settings.selectedModelID, language: settings.selectedLanguage, previewEnabled: settings.livePreview, vocabulary: vocabulary)
    }
}

/// Translate physical shortcut edges into recording commands. Toggle mode intentionally
/// ignores release, while hold mode ends the recording on release.
enum DictationShortcutAction: Equatable {
    case none
    case start
    case stop

    static func resolve(
        _ edge: HotkeyAction,
        mode: RecordingMode,
        state: DictationController.State
    ) -> Self {
        switch (mode, edge, state) {
        case (_, .start, .idle): .start
        case (.toggle, .start, .starting), (.toggle, .start, .listening): .stop
        case (.holdToTalk, .stop, .starting), (.holdToTalk, .stop, .listening): .stop
        default: .none
        }
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var isHotkeyReady = false
    /// Transcript accumulated for cleanup and insertion when recording finishes.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveform.
    private(set) var level: Float = 0

    /// Presentation adapter driving the native voice pill HUD.
    let hudAdapter = HUDPresentationAdapter()
    private(set) var activeSessionID = UUID()
    private let meterLevel = OSAllocatedUnfairLock<Float>(initialState: 0)

    private let hotkey = HotkeyMonitor()
    private var shortcutCaptureSuspended = false
    private var writingAssistantSuspended = false
    private let capture = AudioCapture()
    private let makeEngine: @MainActor @Sendable () -> any TranscriptionEngine

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Chosen per-utterance so the menu toggle applies to the very next hold.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter()
            : RuleBasedFormatter()
    }

    private(set) var lastResult: TextProcessingResult?
    private var destinationPID: pid_t?
    private var destinationBundleID: String?
    private var fieldContext: String?
    private var startupTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the dashboard: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @MainActor @Sendable () -> any TranscriptionEngine = engineForCurrentSetting
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine

        hudAdapter.onStop = { [weak self] in
            self?.stopButtonRecording()
        }
        hudAdapter.onDismiss = { [weak self] in
            self?.dismissHUDError()
        }
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.binding = Settings.shared.shortcut
        hotkey.onPress = { [weak self] in self?.handleShortcut(.start) }
        hotkey.onRelease = { [weak self] in self?.handleShortcut(.stop) }
        isHotkeyReady = hotkey.start()
        return isHotkeyReady
    }

    private func handleShortcut(_ edge: HotkeyAction) {
        switch DictationShortcutAction.resolve(edge, mode: Settings.shared.recordingMode, state: state) {
        case .start: beginDictation()
        case .stop: endDictation()
        case .none: break
        }
    }

    func deactivate() {
        hotkey.stop()
        isHotkeyReady = false
        cancelDictation()
    }

    /// Re-arms the tap after the user picks a different shortcut.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.binding = Settings.shared.shortcut
        isHotkeyReady = hotkey.start()
        return isHotkeyReady
    }

    /// Suspends global hotkey triggering (e.g. while recording a candidate shortcut in settings).
    func suspendHotkey() {
        shortcutCaptureSuspended = true
        hotkey.isSuspended = true
    }

    /// Resumes global hotkey triggering after shortcut editing completes.
    func resumeHotkey() {
        shortcutCaptureSuspended = false
        hotkey.isSuspended = writingAssistantSuspended
    }

    func setWritingAssistantActive(_ active: Bool) {
        writingAssistantSuspended = active
        hotkey.isSuspended = shortcutCaptureSuspended || active
    }

    /// Whether the current recording is an in-app test (prevents pasting into other apps).
    private var isTestMode = false
    private var instructionCompletion: ((Result<String, WritingAssistantError>) -> Void)?

    /// Speech for the assistant prompt never reaches cleanup, history or another app.
    @discardableResult
    func startInstructionDictation(completion: @escaping (Result<String, WritingAssistantError>) -> Void) -> Bool {
        guard state == .idle, !MeetingController.shared.isBusy else { return false }
        instructionCompletion = completion
        isTestMode = true
        beginDictation()
        return true
    }

    func cancelInstructionDictation() {
        guard instructionCompletion != nil else { return }
        instructionCompletion = nil
        cancelDictation()
    }

    /// Starts a recording from a Record button rather than the hotkey.
    ///
    func startButtonRecording(isTest: Bool = false) {
        guard case .idle = state else { return }
        isTestMode = isTest
        beginDictation()
    }

    /// Explicit in-app test dictation that never injects text into other applications.
    func startTestDictation() {
        startButtonRecording(isTest: true)
    }

    func stopButtonRecording() {
        endDictation()
    }

    // MARK: - Dictation

    private func beginDictation() {
        Log.speech.info("beginDictation() — state: \(String(describing: self.state), privacy: .public)")
        guard case .idle = state else {
            Log.speech.warning("beginDictation() ignored — state is not idle: \(String(describing: self.state), privacy: .public)")
            return
        }
        CorrectionLearningMonitor.shared.cancel()
        let sessionID = UUID()
        self.activeSessionID = sessionID
        hudAdapter.sessionDidStart(sessionID: sessionID)

        state = .starting
        transcript = ""
        holdStarted = Date()
        destinationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        destinationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        fieldContext = instructionCompletion == nil ? FocusedTextContext.read() : nil
        lastResult = nil
        if instructionCompletion == nil, Settings.shared.smartCleanup, Settings.shared.writingEngine == .qwen,
           let url = WritingModelManager.shared.selectedModelURL {
            Task { try? await LocalTextRuntime.shared.warmup(modelURL: url) }
        }
        engineName = Settings.shared.engine.displayName

        startupTask = Task { @MainActor [self] in
            do {
                let microphoneAllowed = await Permissions.requestMicrophone()
                guard !Task.isCancelled, self.activeSessionID == sessionID, self.state == .starting else { return }
                guard microphoneAllowed else {
                    fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                guard self.activeSessionID == sessionID, self.state == .starting else { return }
                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()
                guard !Task.isCancelled, self.activeSessionID == sessionID, self.state == .starting else {
                    await Self.cancelEngine(engine)
                    return
                }

                guard let format = await engine.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                guard !Task.isCancelled, self.activeSessionID == sessionID, self.state == .starting else {
                    await Self.cancelEngine(engine)
                    return
                }
                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingOldest(64)
                )
                self.audioContinuation = audioContinuation

                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        guard !Task.isCancelled else { break }
                        await engine.feed(chunk)
                    }
                }

                let meterLevel = self.meterLevel
                let overflowReported = OSAllocatedUnfairLock(initialState: false)
                meterLevel.withLock { $0 = 0 }
                try capture.start(
                    outputFormat: format,
                    selectedMicrophoneID: Settings.shared.selectedMicrophoneID,
                    onBuffer: { @Sendable [weak self] chunk in
                        // A bounded queue must fail visibly rather than silently omit words.
                        if case .dropped = audioContinuation.yield(chunk),
                           overflowReported.withLock({ reported in
                               if reported { return false }
                               reported = true
                               return true
                           }) {
                            Task { @MainActor [weak self] in
                                guard let self, self.activeSessionID == sessionID, self.state.isActive else { return }
                                self.fail("Speech processing fell behind. Please try a faster speech model.")
                            }
                        }
                    },
                    onLevel: { @Sendable level in
                        meterLevel.withLock { $0 = level }
                    }
                )

                // capture.start is synchronous on the main actor. The session guard
                // above therefore also protects capture ownership through this point.
                self.startupTask = nil
                self.state = .listening
                self.hudAdapter.sessionDidBeginListening(sessionID: sessionID) { @Sendable in
                    meterLevel.withLock { $0 }
                }
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            guard !Task.isCancelled, self.activeSessionID == sessionID,
                                  self.state == .listening || self.state == .finishing else { break }
                            self.transcript = chunk.text
                            if Settings.shared.livePreview {
                                self.hudAdapter.sessionDidUpdateTranscript(sessionID: sessionID, text: chunk.text)
                            }
                        }
                    } catch {
                        guard !Task.isCancelled, self.activeSessionID == sessionID else { return }
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                guard !Task.isCancelled, self.activeSessionID == sessionID, self.state == .starting else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        Log.speech.info("endDictation() — state: \(String(describing: self.state), privacy: .public)")
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`, and smart cleanup adds up to 4s on top.
        guard state.isActive, state != .finishing else {
            Log.speech.warning("endDictation() ignored — state not active/already finishing: \(String(describing: self.state), privacy: .public)")
            return
        }
        // Releasing during permission/model startup cancels that pending start. It
        // must never begin microphone capture after the user has released the key.
        if state == .starting {
            let completion = instructionCompletion
            cancelDictation()
            completion?(.success(""))
            return
        }
        let sessionID = self.activeSessionID
        state = .finishing
        hudAdapter.sessionDidBeginTranscribing(sessionID: sessionID)
        capture.stop()
        level = 0
        releasedAt = Date()

        // Capture ownership before suspension. A cancelled completion must never
        // drain, finish or clear the resources belonging to a later recording.
        audioContinuation?.finish()
        audioContinuation = nil
        let sessionFeed = feedTask
        let sessionEngine = engine
        let sessionConsumer = consumeTask
        completionTask = Task { @MainActor in
            await sessionFeed?.value
            guard !Task.isCancelled, activeSessionID == sessionID, state == .finishing else { return }
            await sessionEngine?.finish()
            await sessionConsumer?.value
            guard !Task.isCancelled, activeSessionID == sessionID, state == .finishing else { return }
            feedTask = nil
            consumeTask = nil
            engine = nil

            let raw = transcript
            if let completion = instructionCompletion {
                instructionCompletion = nil
                state = .idle
                isTestMode = false
                transcript = ""
                hudAdapter.sessionDidComplete(sessionID: sessionID, outcome: nil, isNoSpeech: raw.isEmpty)
                completion(.success(raw))
                return
            }
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                isTestMode = false
                hudAdapter.sessionDidComplete(sessionID: sessionID, outcome: nil, isNoSpeech: true)
                return
            }
            hudAdapter.sessionDidBeginCleaning(sessionID: sessionID)
            let result: TextProcessingResult
            if let formatter {
                let text = await formatter.format(raw)
                result = TextProcessingResult(raw: raw, text: text, engine: "Test", styleID: "clean", corrections: [], cleanupSeconds: 0, fallbackReason: nil)
            } else {
                result = await TextProcessingService.shared.process(raw, bundleID: destinationBundleID, fieldContext: fieldContext)
            }
            guard !Task.isCancelled, activeSessionID == sessionID, state == .finishing else { return }
            lastResult = result
            let output = result.text
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                isTestMode = false
                hudAdapter.sessionDidComplete(sessionID: sessionID, outcome: nil, isNoSpeech: true)
                return
            }
            recordRun(result: result)
            hudAdapter.sessionDidBeginDelivering(sessionID: sessionID)
            let outcome: MurmurHUDOutcome
            if !isTestMode {
                let learningTarget = CorrectionLearningMonitor.shared.capture(inserted: output, expectedPID: destinationPID)
                outcome = TextInjector.insert(output, expectedPID: destinationPID)
                if outcome != .copied { CorrectionLearningMonitor.shared.observe(learningTarget) }
            } else {
                Log.inject.info("Test dictation completed — text intentionally not inserted outside Murmur")
                outcome = .transcribed
            }
            isTestMode = false
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            state = .idle
            transcript = ""
            hudAdapter.sessionDidComplete(sessionID: sessionID, outcome: outcome)
        }
    }

    private func cancelDictation() {
        instructionCompletion = nil
        startupTask?.cancel()
        startupTask = nil
        completionTask?.cancel()
        completionTask = nil
        let sessionID = self.activeSessionID
        hudAdapter.sessionDidCancel(sessionID: sessionID)
        activeSessionID = UUID()
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        isTestMode = false
        let engine = self.engine
        self.engine = nil
        Task { await Self.cancelEngine(engine) }

        state = .idle
        transcript = ""
        level = 0
    }

    private static func cancelEngine(_ engine: (any TranscriptionEngine)?) async {
        if let cancellable = engine as? any CancellableTranscriptionEngine {
            await cancellable.cancel()
        } else {
            await engine?.finish()
        }
    }

    // MARK: - Helpers

    /// Files the finished utterance for the dashboard.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(result: TextProcessingResult) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: result.text,
                corrections: result.corrections.isEmpty ? nil : result.corrections,
                rawText: result.raw, bundleID: destinationBundleID,
                styleID: result.styleID, cleanupEngine: result.engine,
                cleanupSeconds: result.cleanupSeconds, fallbackReason: result.fallbackReason
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        let instructionFailure = instructionCompletion
        instructionCompletion = nil
        Log.app.error("\(message)")
        let sessionID = self.activeSessionID
        hudAdapter.sessionDidFail(sessionID: sessionID, message: message)

        startupTask?.cancel()
        startupTask = nil
        completionTask?.cancel()
        completionTask = nil
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        let failedEngine = engine
        engine = nil
        Task { await Self.cancelEngine(failedEngine) }
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        instructionFailure?(.failure(WritingAssistantError(message: message)))
        level = 0
        isTestMode = false

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard self.activeSessionID == sessionID else { return }
            if case .error = self.state { self.state = .idle }
        }
    }

    func dismissHUDError() {
        hudAdapter.manualDismiss(sessionID: activeSessionID)
        if case .error = state {
            state = .idle
        }
    }
}
