import AVFoundation
import Foundation

/// Microphone capture with on-the-fly conversion to whatever format the speech engine wants.
///
/// The tap runs on a real-time audio thread, so everything it touches is explicitly `nonisolated`
/// and only ever mutated from that one thread while running.
nonisolated final class AudioCapture: @unchecked Sendable {
    private nonisolated(unsafe) var engine: AVAudioEngine?
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private var hasInstalledTap = false
    private var isRunning = false

    /// Called on the audio thread with each converted buffer.
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    /// Called on the audio thread with a 0…1 RMS level, for the HUD waveform.
    private nonisolated(unsafe) var onLevel: (@Sendable (Float) -> Void)?

    nonisolated init() {}

    nonisolated func start(
        outputFormat: AVAudioFormat,
        selectedMicrophoneID: String = "system_default",
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard !isRunning else { return }
        guard AudioTapProcessor.isValidFormat(outputFormat) else {
            throw TranscriptionError.noAudioFormat
        }

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode

        if let resolved = CoreAudioHardware.resolveInputDevice(for: selectedMicrophoneID) {
            if !CoreAudioHardware.setInputDevice(resolved.deviceID, on: input),
               let defaultID = CoreAudioHardware.defaultInputDeviceID(),
               defaultID != resolved.deviceID {
                _ = CoreAudioHardware.setInputDevice(defaultID, on: input)
            }
        }

        newEngine.reset()

        guard let nativeFormat = AudioTapProcessor.validatedTapFormat(for: input) else {
            throw TranscriptionError.noAudioFormat
        }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.outputFormat = outputFormat
        self.engine = newEngine

        converter = nativeFormat == outputFormat
            ? nil
            : AVAudioConverter(from: nativeFormat, to: outputFormat)

        if hasInstalledTap {
            input.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        let tapBlock: AVAudioNodeTapBlock = { @Sendable [weak self] buffer, _ in
            self?.handle(buffer)
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat, block: tapBlock)
        hasInstalledTap = true

        do {
            newEngine.prepare()
            try newEngine.start()
            isRunning = true
            Log.audio.info("capture started — native \(nativeFormat.sampleRate)Hz → engine \(outputFormat.sampleRate)Hz")
        } catch {
            input.removeTap(onBus: 0)
            hasInstalledTap = false
            newEngine.stop()
            newEngine.reset()
            self.engine = nil
            self.converter = nil
            self.outputFormat = nil
            self.onBuffer = nil
            self.onLevel = nil
            self.isRunning = false
            throw error
        }
    }

    nonisolated func stop() {
        guard isRunning || hasInstalledTap || engine != nil else { return }
        if let activeEngine = engine {
            if hasInstalledTap {
                activeEngine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            if activeEngine.isRunning {
                activeEngine.stop()
            }
            activeEngine.reset()
        }
        engine = nil
        hasInstalledTap = false
        isRunning = false
        converter = nil
        outputFormat = nil
        onBuffer = nil
        onLevel = nil
        Log.audio.info("capture stopped")
    }

    // MARK: - Audio thread

    nonisolated private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(AudioTapProcessor.computeNormalizedLevel(from: buffer))

        guard let outputFormat else { return }

        // AVAudioEngine reuses the tap's buffer as soon as this returns, so the engine
        // must never see it directly — copy when no conversion would otherwise allocate.
        guard let converter else {
            if let copy = Self.copy(buffer) {
                onBuffer?(AudioChunk(buffer: copy))
            }
            return
        }

        guard buffer.format.sampleRate > 0 else { return }

        // Output frame count scales with the sample-rate ratio; round up so we never clip.
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // The input block runs synchronously inside `convert`, on this thread.
        nonisolated(unsafe) let input = buffer
        let consumed = Latch()
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { @Sendable _, outStatus in
            guard !consumed.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }

        if let error {
            Log.audio.error("conversion failed: \(error.localizedDescription)")
            return
        }
        guard status != .error, converted.frameLength > 0 else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }

    /// Deep-copies a tap buffer into storage we own.
    nonisolated private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }

        return copy
    }

    /// One-shot flag. Only touched from the audio thread inside a synchronous call.
    nonisolated private final class Latch: @unchecked Sendable {
        private var fired = false
        /// - Returns: the value *before* this call, then latches to `true`.
        nonisolated func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }
}
