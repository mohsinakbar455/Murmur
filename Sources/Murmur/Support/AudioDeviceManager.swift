import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Observation
import os

/// Information about an audio input device.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let audioDeviceID: AudioDeviceID?
    public let sampleRate: Double
    public let inputChannels: Int

    public init(
        id: String,
        name: String,
        isDefault: Bool = false,
        audioDeviceID: AudioDeviceID? = nil,
        sampleRate: Double = 0,
        inputChannels: Int = 1
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.audioDeviceID = audioDeviceID
        self.sampleRate = sampleRate
        self.inputChannels = inputChannels
    }
}

/// Resolution result when mapping a user-selected microphone identifier to an active CoreAudio device.
public struct ResolvedAudioInputDevice: Equatable, Sendable {
    public let deviceID: AudioDeviceID
    public let uid: String
    public let name: String
    public let sampleRate: Double
    public let inputChannels: Int
    public let didFallbackToDefault: Bool
}

/// Snapshot of CoreAudio hardware state used to detect meaningful input/output device and format changes
/// while ignoring transient internal aggregate devices created by AVAudioEngine.
private struct HardwareStateSignature: Equatable, Sendable {
    struct DeviceSignature: Equatable, Sendable {
        let deviceID: AudioDeviceID
        let uid: String
        let sampleRate: Int
        let inputChannels: Int
    }

    let inputDevices: [DeviceSignature]
    let defaultInputDeviceID: AudioDeviceID
    let defaultOutputDeviceID: AudioDeviceID
    let defaultInputSampleRate: Int
    let defaultOutputSampleRate: Int
}

/// Nonisolated helper for CoreAudio HAL queries and property listeners so C/ObjC listener blocks
/// never inherit `@MainActor` isolation.
nonisolated enum CoreAudioHardware {
    private static let listenerQueue = DispatchQueue(
        label: "ai.pivotstudio.murmur.coreaudio-listener",
        qos: .userInitiated
    )

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    nonisolated static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    nonisolated static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        return deviceIDs
    }

    nonisolated static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var cfUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfUID)
        guard status == noErr, let value = cfUID?.takeRetainedValue() else { return nil }
        return value as String
    }

    nonisolated static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfName)
        guard status == noErr, let value = cfName?.takeRetainedValue() else { return nil }
        return value as String
    }

    nonisolated static func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return true }
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        guard status == noErr else { return false }
        return alive != 0
    }

    nonisolated static func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return 0 }
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return status == noErr ? transport : 0
    }

    nonisolated static func nominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return 0 }
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        return sampleRate
    }

    nonisolated static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return 0 }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return 0
        }

        let byteCount = Int(size)
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPtr)
        guard status == noErr else { return 0 }

        let bufferListPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        var totalChannels = 0
        for buffer in buffers {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return totalChannels
    }

    nonisolated static func isInternalAggregateDevice(uid: String, name: String) -> Bool {
        if uid.contains("CADefaultDeviceAggregate") || name.contains("CADefaultDeviceAggregate") {
            return true
        }
        if uid.contains("VPAUAggregate") || name.contains("VPAUAggregate") {
            return true
        }
        return false
    }

    /// Enumerates all currently alive, user-facing CoreAudio input devices.
    nonisolated static func availableInputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        let defaultUID = defaultID.flatMap { deviceUID(for: $0) }

        var result: [AudioInputDevice] = []
        var seenUIDs = Set<String>()

        for deviceID in allDeviceIDs() {
            guard isDeviceAlive(deviceID) else { continue }
            let channels = inputChannelCount(for: deviceID)
            guard channels > 0 else { continue }
            guard let uid = deviceUID(for: deviceID), !uid.isEmpty else { continue }
            let name = deviceName(for: deviceID) ?? uid
            guard !isInternalAggregateDevice(uid: uid, name: name) else { continue }

            let rate = nominalSampleRate(for: deviceID)
            guard rate > 0 else { continue }

            let isDef = (deviceID == defaultID) || (uid == defaultUID)
            seenUIDs.insert(uid)
            result.append(
                AudioInputDevice(
                    id: uid,
                    name: name,
                    isDefault: isDef,
                    audioDeviceID: deviceID,
                    sampleRate: rate,
                    inputChannels: channels
                )
            )
        }

        // Supplement with AVCaptureDevice.DiscoverySession if any audio capture device was not yet listed
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone, .external]
        } else {
            deviceTypes = [.builtInMicrophone, .external]
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        let avDefaultUID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? defaultUID
        for dev in session.devices where !seenUIDs.contains(dev.uniqueID) {
            guard !isInternalAggregateDevice(uid: dev.uniqueID, name: dev.localizedName) else { continue }
            seenUIDs.insert(dev.uniqueID)
            result.append(
                AudioInputDevice(
                    id: dev.uniqueID,
                    name: dev.localizedName,
                    isDefault: dev.uniqueID == avDefaultUID,
                    audioDeviceID: nil,
                    sampleRate: 48_000,
                    inputChannels: 1
                )
            )
        }

        return result
    }

    /// Resolves the desired input device UID (or `"system_default"`) to a live CoreAudio `AudioDeviceID`.
    /// Preserves the user's preference when available and falls back gracefully to the system default
    /// input device if the selected device was disconnected.
    nonisolated static func resolveInputDevice(for selectedMicrophoneID: String) -> ResolvedAudioInputDevice? {
        let liveDevices = availableInputDevices().compactMap { device -> ResolvedAudioInputDevice? in
            guard let deviceID = device.audioDeviceID,
                  device.sampleRate > 0,
                  device.inputChannels > 0 else {
                return nil
            }
            return ResolvedAudioInputDevice(
                deviceID: deviceID,
                uid: device.id,
                name: device.name,
                sampleRate: device.sampleRate,
                inputChannels: device.inputChannels,
                didFallbackToDefault: false
            )
        }

        guard !liveDevices.isEmpty else { return nil }

        if selectedMicrophoneID != "system_default" {
            if let matched = liveDevices.first(where: { $0.uid == selectedMicrophoneID }) {
                return matched
            }
            // Selected device is disconnected/unavailable: fall back gracefully to system default
            if let defaultID = defaultInputDeviceID(),
               let fallback = liveDevices.first(where: { $0.deviceID == defaultID }) {
                return ResolvedAudioInputDevice(
                    deviceID: fallback.deviceID,
                    uid: fallback.uid,
                    name: fallback.name,
                    sampleRate: fallback.sampleRate,
                    inputChannels: fallback.inputChannels,
                    didFallbackToDefault: true
                )
            }
            if let first = liveDevices.first {
                return ResolvedAudioInputDevice(
                    deviceID: first.deviceID,
                    uid: first.uid,
                    name: first.name,
                    sampleRate: first.sampleRate,
                    inputChannels: first.inputChannels,
                    didFallbackToDefault: true
                )
            }
            return nil
        }

        if let defaultID = defaultInputDeviceID(),
           let defaultMatch = liveDevices.first(where: { $0.deviceID == defaultID }) {
            return defaultMatch
        }
        return liveDevices.first
    }

    /// Binds a CoreAudio `AudioDeviceID` to an `AVAudioInputNode`'s underlying AudioUnit.
    @discardableResult
    nonisolated static func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) -> Bool {
        guard isDeviceAlive(deviceID), inputChannelCount(for: deviceID) > 0 else {
            return false
        }
        guard let audioUnit = inputNode.audioUnit else {
            return false
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    /// Installs CoreAudio system hardware listeners outside `@MainActor` so the C/ObjC block
    /// never inherits `@MainActor` isolation.
    nonisolated static func installSystemHardwareListeners(
        onHardwareEvent: @escaping @Sendable () -> Void
    ) {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice
        ]

        let block: AudioObjectPropertyListenerBlock = { @Sendable _, _ in
            onHardwareEvent()
        }

        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                block
            )
        }
    }
}

/// Discovers and tracks real audio input and output devices available on the system.
@MainActor
@Observable
public final class AudioDeviceManager {
    public static let shared = AudioDeviceManager()

    public private(set) var devices: [AudioInputDevice] = []
    public private(set) var defaultDevice: AudioInputDevice?
    /// Incremented whenever the underlying input/output hardware topology or sample rate changes.
    public private(set) var hardwareChangeRevision: UInt64 = 0

    private var lastSignature: HardwareStateSignature?
    private var coalesceTask: Task<Void, Never>?

    private init() {
        refreshDevices()
        observeDeviceChanges()
    }

    /// Refreshes the list of available audio input devices.
    /// - Returns: `true` if the real input/output hardware state changed since the last refresh.
    @discardableResult
    public func refreshDevices() -> Bool {
        let discovered = CoreAudioHardware.availableInputDevices()
        let defaultInputID = CoreAudioHardware.defaultInputDeviceID()
        let defaultOutputID = CoreAudioHardware.defaultOutputDeviceID()

        if let defaultDev = discovered.first(where: { $0.isDefault }) ?? discovered.first {
            self.defaultDevice = defaultDev
        } else if let avDefault = AVCaptureDevice.default(for: .audio) {
            self.defaultDevice = AudioInputDevice(
                id: avDefault.uniqueID,
                name: avDefault.localizedName,
                isDefault: true
            )
        } else {
            self.defaultDevice = nil
        }

        if discovered.isEmpty {
            self.devices = [
                AudioInputDevice(
                    id: "system_default",
                    name: "System Default Microphone",
                    isDefault: true
                )
            ]
        } else {
            self.devices = discovered
        }

        let newSignature = HardwareStateSignature(
            inputDevices: discovered.compactMap { dev in
                guard let id = dev.audioDeviceID else { return nil }
                return HardwareStateSignature.DeviceSignature(
                    deviceID: id,
                    uid: dev.id,
                    sampleRate: Int(dev.sampleRate.rounded()),
                    inputChannels: dev.inputChannels
                )
            },
            defaultInputDeviceID: defaultInputID ?? AudioDeviceID(kAudioObjectUnknown),
            defaultOutputDeviceID: defaultOutputID ?? AudioDeviceID(kAudioObjectUnknown),
            defaultInputSampleRate: Int((defaultInputID.map { CoreAudioHardware.nominalSampleRate(for: $0) } ?? 0).rounded()),
            defaultOutputSampleRate: Int((defaultOutputID.map { CoreAudioHardware.nominalSampleRate(for: $0) } ?? 0).rounded())
        )

        let didChange: Bool
        if let previous = lastSignature {
            didChange = (previous != newSignature)
        } else {
            didChange = false
        }
        lastSignature = newSignature

        if didChange {
            hardwareChangeRevision &+= 1
            Log.audio.info("Audio hardware configuration changed (revision \(self.hardwareChangeRevision, privacy: .public))")
        }
        return didChange
    }

    private func scheduleHardwareRefresh() {
        coalesceTask?.cancel()
        coalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }
            self.refreshDevices()
        }
    }

    private func observeDeviceChanges() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHardwareRefresh()
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleHardwareRefresh()
            }
        }

        CoreAudioHardware.installSystemHardwareListeners { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleHardwareRefresh()
            }
        }
    }
}
