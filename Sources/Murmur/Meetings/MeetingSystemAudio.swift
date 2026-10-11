import AVFoundation
import CoreAudio
import Foundation

/// A scoped native Core Audio tap. No virtual driver and no capture-all fallback.
final class MeetingSystemAudio: @unchecked Sendable {
    private var processTap: AudioObjectID = kAudioObjectUnknown
    private var aggregate: AudioObjectID = kAudioObjectUnknown
    private var callback: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let conversionLock = NSLock()
    private var deliver: (@Sendable ([Float]) -> Void)?
    private(set) var outputDevice: AudioObjectID = kAudioObjectUnknown

    func start(source: MeetingCaptureSource, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        guard source.includesSystemAudio else { return }
        let description: CATapDescription
        switch source {
        case .microphone: return
        case .microphoneAndSystem:
            description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        case .microphoneAndApp(let bundleID, let name):
            let processes = try Self.processes(for: bundleID)
            guard !processes.isEmpty else {
                throw MeetingCaptureError.message("No audio process was found for \(name). Open the call in that app, play audio, and try again. Only the selected app will be captured.")
            }
            description = CATapDescription(monoMixdownOfProcesses: processes)
        }
        description.name = "Murmur meeting audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        do {
            try Self.check(AudioHardwareCreateProcessTap(description, &processTap), "Allow Murmur in System Settings → Privacy & Security → Screen & System Audio Recording, then try again")
            outputDevice = try Self.defaultOutput()
            let outputUID = try Self.stringProperty(outputDevice, selector: kAudioDevicePropertyDeviceUID)
            let specification: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Murmur meeting capture",
                kAudioAggregateDeviceUIDKey: "ai.pivotstudio.murmur.meeting.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(specification as CFDictionary, &aggregate), "Could not create the meeting audio device")
            var property = Self.address(kAudioTapPropertyFormat)
            var stream = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(processTap, &property, 0, nil, &size, &stream), "Could not read the system audio format")
            guard let inputFormat = AVAudioFormat(streamDescription: &stream),
                  let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let audioConverter = AVAudioConverter(from: inputFormat, to: target) else {
                throw MeetingCaptureError.message("This output device has an unsupported meeting audio format.")
            }
            format = inputFormat
            converter = audioConverter
            deliver = onSamples
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&callback, aggregate, nil) { [weak self] _, input, _, _, _ in
                self?.receive(input)
            }, "Could not attach system audio capture")
            try Self.check(AudioDeviceStart(aggregate, callback), "Could not start system audio capture")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let callback, aggregate != kAudioObjectUnknown {
            AudioDeviceStop(aggregate, callback)
            AudioDeviceDestroyIOProcID(aggregate, callback)
        }
        callback = nil
        conversionLock.lock()
        deliver = nil
        converter = nil
        format = nil
        conversionLock.unlock()
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = kAudioObjectUnknown }
        if processTap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(processTap); processTap = kAudioObjectUnknown }
    }

    deinit { stop() }

    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        conversionLock.lock(); defer { conversionLock.unlock() }
        guard let format, let converter,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
              buffer.frameLength > 0 else { return }
        let frames = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / format.sampleRate)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frames) else { return }
        // The converter invokes this synchronously; the borrowed input never escapes the callback.
        nonisolated(unsafe) let borrowed = buffer
        let once = ConversionInput()
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if once.consumed { status.pointee = .noDataNow; return nil }
            once.consumed = true
            status.pointee = .haveData
            return borrowed
        }
        guard error == nil, converted.frameLength > 0, let channel = converted.floatChannelData?[0] else { return }
        deliver?(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
    }

    private final class ConversionInput: @unchecked Sendable { var consumed = false }

    static func defaultOutput() throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device), "No output device is available")
        return device
    }

    private static func processes(for bundleID: String) throws -> [AudioObjectID] {
        var property = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        try check(AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size), "Could not list app audio sources")
        var all = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(system, &property, 0, nil, &size, &all), "Could not inspect app audio sources")
        return all.filter { process in
            guard let candidate = try? stringProperty(process, selector: kAudioProcessPropertyBundleID) else { return false }
            return candidate == bundleID || candidate.hasPrefix(bundleID + ".")
        }
    }

    private static func stringProperty(_ object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        // Core Audio returns an owned CFObject for these properties. Use unmanaged
        // pointer storage so C does not overwrite a Swift-managed reference slot.
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &reference), "Could not identify an audio device")
        guard let reference else { throw MeetingCaptureError.message("The audio device returned no identifier.") }
        return reference.takeRetainedValue() as String
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func check(_ status: OSStatus, _ message: String) throws {
        guard status == noErr else { throw MeetingCaptureError.message("\(message). (Audio error \(status))") }
    }
}

enum MeetingCaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}
