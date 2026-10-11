import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Observation
import os

/// Thread-safe, lock-protected gate that coalesces real-time audio meter updates to ~24 Hz
/// (within the 15–30 Hz UI update window) and blocks stale callbacks after a test stops.
nonisolated struct MeterUpdateGate: Sendable {
    private struct State: Sendable {
        var isActive: Bool = false
        var generation: UInt64 = 0
        var lastEmitUptime: TimeInterval = 0
        var smoothedLevel: Float = 0
    }

    /// Minimum interval between UI hops (~24 Hz = 41.6 ms).
    private static let minimumEmitInterval: TimeInterval = 1.0 / 24.0

    private let state = OSAllocatedUnfairLock(initialState: State())

    nonisolated init() {}

    nonisolated func activate(generation: UInt64) {
        state.withLock { s in
            s.isActive = true
            s.generation = generation
            s.lastEmitUptime = 0
            s.smoothedLevel = 0
        }
    }

    nonisolated func deactivate() {
        state.withLock { s in
            s.isActive = false
            s.smoothedLevel = 0
        }
    }

    /// Records a scalar level from the real-time audio thread and returns a coalesced level
    /// only when the throttle interval has elapsed and the generation is still active.
    nonisolated func recordAndShouldEmit(
        rawLevel: Float,
        generation: UInt64,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Float? {
        let sanitized = rawLevel.isFinite ? max(0, min(1, rawLevel)) : 0
        return state.withLock { s -> Float? in
            guard s.isActive, s.generation == generation else {
                return nil
            }
            // Fast attack, smooth decay so brief speech peaks between 24 Hz ticks are preserved.
            if sanitized >= s.smoothedLevel {
                s.smoothedLevel = sanitized
            } else {
                s.smoothedLevel = s.smoothedLevel * 0.65 + sanitized * 0.35
            }

            guard now - s.lastEmitUptime >= Self.minimumEmitInterval else {
                return nil
            }
            s.lastEmitUptime = now
            return s.smoothedLevel
        }
    }
}

/// Purely nonisolated audio tap installation and synchronous PCM buffer metering.
///
/// Kept in a top-level `nonisolated` namespace so that tap closures are never formed inside
/// a `@MainActor` method or type and never inherit `@MainActor` isolation.
nonisolated enum AudioTapProcessor {
    /// Validates that an `AVAudioFormat` has a positive, finite sample rate and at least one channel.
    nonisolated static func isValidFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate.isFinite && format.sampleRate > 0 && format.channelCount > 0
    }

    /// Resolves and validates the tap format for `inputNode` after a hardware device change.
    /// Queries both hardware input format and bus output format to prevent AVFAudio assertions.
    nonisolated static func validatedTapFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let busFormat = inputNode.outputFormat(forBus: 0)

        guard isValidFormat(hwFormat), isValidFormat(busFormat) else {
            return nil
        }

        if busFormat.commonFormat == .pcmFormatFloat32 && !busFormat.isInterleaved {
            return busFormat
        }
        return AVAudioFormat(
            standardFormatWithSampleRate: busFormat.sampleRate,
            channels: busFormat.channelCount
        )
    }

    /// Synchronously calculates a normalized `0...1` RMS level from a PCM buffer on the audio thread.
    /// Never escapes `buffer`, allocates no heap memory, and performs no logging or I/O.
    nonisolated static func computeNormalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumSquares: Float = 0
        var sampleCount: Int = 0

        if let floatData = buffer.floatChannelData {
            let samples = floatData[0]
            let count = buffer.format.isInterleaved ? frameLength * channelCount : frameLength
            guard count > 0 else { return 0 }
            for i in 0..<count {
                let s = samples[i]
                if s.isFinite {
                    sumSquares += s * s
                }
            }
            sampleCount = count
        } else if let int16Data = buffer.int16ChannelData {
            let samples = int16Data[0]
            let count = buffer.format.isInterleaved ? frameLength * channelCount : frameLength
            guard count > 0 else { return 0 }
            let scale = 1.0 / Float(Int16.max)
            for i in 0..<count {
                let s = Float(samples[i]) * scale
                sumSquares += s * s
            }
            sampleCount = count
        } else if let int32Data = buffer.int32ChannelData {
            let samples = int32Data[0]
            let count = buffer.format.isInterleaved ? frameLength * channelCount : frameLength
            guard count > 0 else { return 0 }
            let scale = 1.0 / Float(Int32.max)
            for i in 0..<count {
                let s = Float(samples[i]) * scale
                sumSquares += s * s
            }
            sampleCount = count
        } else {
            return 0
        }

        guard sampleCount > 0 else { return 0 }
        let meanSquare = sumSquares / Float(sampleCount)
        guard meanSquare.isFinite, meanSquare > 0 else { return 0 }

        let rms = meanSquare.squareRoot()
        let db = 20.0 * log10(max(rms, 1e-7))
        let normalized = max(0.0, min(1.0, (db + 50.0) / 50.0))
        return normalized.isFinite ? normalized : 0
    }

    /// Installs the input tap from a strictly nonisolated context so the callback closure
    /// can safely execute on `RealtimeMessenger.mServiceQueue` without MainActor assertions.
    nonisolated static func installMeterTap(
        on inputNode: AVAudioInputNode,
        bufferSize: AVAudioFrameCount = 1024,
        format: AVAudioFormat,
        generation: UInt64,
        gate: MeterUpdateGate,
        onCoalescedLevel: @escaping @Sendable (UInt64, Float) -> Void
    ) {
        let tapBlock: AVAudioNodeTapBlock = { @Sendable buffer, _ in
            let rawLevel = Self.computeNormalizedLevel(from: buffer)
            guard let coalesced = gate.recordAndShouldEmit(rawLevel: rawLevel, generation: generation) else {
                return
            }
            onCoalescedLevel(generation, coalesced)
        }
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tapBlock)
    }

    /// Observes `AVAudioEngineConfigurationChange` from a nonisolated context and forwards
    /// to the provided `@Sendable` handler.
    nonisolated static func observeConfigurationChange(
        for engine: AVAudioEngine,
        handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { @Sendable _ in
            handler()
        }
    }
}

/// Dedicated controller managing the Settings microphone test lifecycle, tap installation,
/// level metering, and live input/output audio device switching.
@MainActor
@Observable
public final class MicTestController {
    public private(set) var isTesting: Bool = false
    public private(set) var level: Float = 0
    public private(set) var errorMessage: String? = nil

    private var activeEngine: AVAudioEngine?
    private var activeInputNode: AVAudioInputNode?
    private var hasInstalledTap: Bool = false
    private var configChangeObserver: NSObjectProtocol?

    private var activeGeneration: UInt64 = 0
    private var isTransitioning: Bool = false
    private var isRequestingPermission: Bool = false
    private var reconfigurationTask: Task<Void, Never>?

    private let meterGate = MeterUpdateGate()

    public init() {}

    isolated deinit {
        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        meterGate.deactivate()
        tearDownEngine()
    }

    // MARK: - Public Lifecycle

    /// Starts the microphone test idempotently.
    /// Rapid repeated calls will not install duplicate taps or start overlapping engines.
    public func startMicTest(isDictationActive: Bool = false) {
        guard !isDictationActive else { return }

        // Idempotent guard: already running cleanly or in the middle of starting/requesting permission.
        if isTransitioning || isRequestingPermission {
            return
        }
        if isTesting, hasInstalledTap, activeEngine?.isRunning == true, errorMessage == nil {
            return
        }

        reconfigurationTask?.cancel()
        reconfigurationTask = nil

        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authStatus {
        case .denied, .restricted:
            tearDownEngine()
            isTesting = false
            level = 0
            errorMessage = "Microphone access is denied in System Settings."
            return

        case .notDetermined:
            isRequestingPermission = true
            errorMessage = nil
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isRequestingPermission = false
                    if granted {
                        self.startMicTest(isDictationActive: false)
                    } else {
                        self.tearDownEngine()
                        self.isTesting = false
                        self.level = 0
                        self.errorMessage = "Microphone access was denied."
                    }
                }
            }
            return

        case .authorized:
            break

        @unknown default:
            tearDownEngine()
            isTesting = false
            level = 0
            errorMessage = "Unable to verify microphone authorization."
            return
        }

        errorMessage = nil
        level = 0
        _ = configureAndStartEngine(
            selectedMicrophoneID: Settings.shared.selectedMicrophoneID,
            allowTransientFailure: false
        )
    }

    /// Stops the microphone test idempotently, removing any installed tap and resetting state.
    public func stopMicTest() {
        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        activeGeneration &+= 1
        meterGate.deactivate()
        tearDownEngine()
        isTransitioning = false
        isTesting = false
        level = 0
        errorMessage = nil
    }

    /// Handles a user-initiated change to the selected microphone in Settings.
    public func handleSelectedMicrophoneChange(to newMicrophoneID: String, isDictationActive: Bool = false) {
        if isDictationActive {
            stopMicTest()
            return
        }
        guard isTesting else {
            // If not actively testing, clear any stale error from a previously selected device.
            if errorMessage != nil {
                errorMessage = nil
            }
            return
        }
        scheduleReconfiguration(selectedMicrophoneID: newMicrophoneID)
    }

    /// Handles CoreAudio input/output device connections, disconnections, default device changes,
    /// or Bluetooth/AirPods profile and sample-rate transitions.
    public func handleHardwareChange(isDictationActive: Bool = false) {
        if isDictationActive {
            stopMicTest()
            return
        }
        guard isTesting else { return }
        scheduleReconfiguration(selectedMicrophoneID: Settings.shared.selectedMicrophoneID)
    }

    // MARK: - Internal Engine & Tap Serialization

    private func scheduleReconfiguration(selectedMicrophoneID: String) {
        guard isTesting else { return }

        // Immediately stop the old engine and remove the old tap before the hardware transition settles.
        activeGeneration &+= 1
        meterGate.deactivate()
        tearDownEngine()
        level = 0
        errorMessage = nil

        reconfigurationTask?.cancel()
        reconfigurationTask = Task { @MainActor [weak self] in
            guard let self, self.isTesting else { return }

            // Refresh device catalog to pick up newly connected/disconnected devices or sample rates.
            AudioDeviceManager.shared.refreshDevices()

            // Bluetooth/AirPods profile transitions (A2DP -> HFP) can briefly report 0 Hz or fail
            // AudioUnit start while negotiating the SCO/HFP link. Retry up to 3 times before failing.
            let maxAttempts = 3
            for attempt in 0..<maxAttempts {
                guard !Task.isCancelled, self.isTesting else { return }
                let isFinalAttempt = (attempt == maxAttempts - 1)
                let succeeded = self.configureAndStartEngine(
                    selectedMicrophoneID: selectedMicrophoneID,
                    allowTransientFailure: !isFinalAttempt
                )
                if succeeded {
                    return
                }
                if !isFinalAttempt {
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }

    @discardableResult
    private func configureAndStartEngine(
        selectedMicrophoneID: String,
        allowTransientFailure: Bool
    ) -> Bool {
        isTransitioning = true
        defer { isTransitioning = false }

        // Ensure any prior tap and engine are completely torn down before creating a new graph.
        tearDownEngine()

        AudioDeviceManager.shared.refreshDevices()

        guard let resolvedDevice = CoreAudioHardware.resolveInputDevice(for: selectedMicrophoneID) else {
            if !allowTransientFailure {
                isTesting = false
                level = 0
                errorMessage = "No working microphone input device is available."
            }
            return false
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Bind the resolved CoreAudio device ID to the input node's AudioUnit.
        if !CoreAudioHardware.setInputDevice(resolvedDevice.deviceID, on: inputNode) {
            // If a specific device failed to bind, attempt graceful fallback to the system default.
            if let defaultID = CoreAudioHardware.defaultInputDeviceID(),
               defaultID != resolvedDevice.deviceID,
               CoreAudioHardware.setInputDevice(defaultID, on: inputNode) {
                Log.audio.info("MicTestController fell back to system default input device")
            } else {
                if !allowTransientFailure {
                    isTesting = false
                    level = 0
                    errorMessage = "Selected microphone is unavailable."
                }
                return false
            }
        }

        // Reset the engine after changing the underlying AudioUnit device so bus formats re-sync.
        engine.reset()

        // Always query the new device's format after binding; never reuse an old AVAudioFormat.
        guard let tapFormat = AudioTapProcessor.validatedTapFormat(for: inputNode) else {
            if !allowTransientFailure {
                isTesting = false
                level = 0
                errorMessage = "Could not initialize audio input format for the selected microphone."
            }
            return false
        }

        activeGeneration &+= 1
        let generation = activeGeneration
        meterGate.activate(generation: generation)

        // Ensure no previous tap exists on bus 0 before installing.
        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        AudioTapProcessor.installMeterTap(
            on: inputNode,
            bufferSize: 1024,
            format: tapFormat,
            generation: generation,
            gate: meterGate,
            onCoalescedLevel: { [weak self] callbackGeneration, coalescedLevel in
                Task { @MainActor [weak self] in
                    self?.applyCoalescedLevel(coalescedLevel, generation: callbackGeneration)
                }
            }
        )
        hasInstalledTap = true
        activeEngine = engine
        activeInputNode = inputNode

        do {
            engine.prepare()
            try engine.start()
            isTesting = true
            errorMessage = nil

            // Observe mid-stream configuration changes (e.g. Bluetooth sample-rate switch or output route change).
            configChangeObserver = AudioTapProcessor.observeConfigurationChange(for: engine) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isTesting, !self.isTransitioning, self.activeGeneration == generation else {
                        return
                    }
                    self.scheduleReconfiguration(selectedMicrophoneID: Settings.shared.selectedMicrophoneID)
                }
            }

            Log.audio.info(
                "Mic test started on \(resolvedDevice.name, privacy: .public) (\(tapFormat.sampleRate, privacy: .public) Hz, \(tapFormat.channelCount, privacy: .public) ch)"
            )
            return true
        } catch {
            // Clean up the newly installed tap immediately if engine.start() fails.
            meterGate.deactivate()
            tearDownEngine()
            if !allowTransientFailure {
                isTesting = false
                level = 0
                errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            }
            Log.audio.error("Mic test failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func tearDownEngine() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if hasInstalledTap, let inputNode = activeInputNode {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        } else {
            hasInstalledTap = false
        }
        if let engine = activeEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
            activeEngine = nil
        }
        activeInputNode = nil
    }

    private func applyCoalescedLevel(_ newLevel: Float, generation: UInt64) {
        guard isTesting, !isTransitioning, activeGeneration == generation else { return }
        level = newLevel
    }
}
