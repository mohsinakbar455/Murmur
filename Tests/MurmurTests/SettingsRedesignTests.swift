import Testing
import AVFoundation
import Foundation
@testable import Murmur

@Suite("Settings Redesign Tests")
struct SettingsRedesignTests {

    @Test("Exact 5 sections hierarchy and row ordering")
    func sectionHierarchyAndRowOrdering() {
        let allSections = SettingsSectionID.allCases
        #expect(allSections.count == 5)
        #expect(allSections[0] == .dictationAudio)
        #expect(allSections[1] == .textCleanup)
        #expect(allSections[2] == .personalization)
        #expect(allSections[3] == .privacyData)
        #expect(allSections[4] == .advanced)

        // Verify Dictation & audio rows
        let dictationRows = SettingsSectionID.dictationAudio.rows
        #expect(dictationRows == [.shortcut, .recordingMode, .microphone, .transcriptionLanguage, .recordingSounds, .livePreview, .floatingPill])

        // Verify Text cleanup rows
        let cleanupRows = SettingsSectionID.textCleanup.rows
        #expect(cleanupRows == [.automaticFormatting, .writingEngine, .smartCleanup, .fieldContext, .writingAssistant])

        // Verify Personalization rows
        let personalizationRows = SettingsSectionID.personalization.rows
        #expect(personalizationRows == [.displayName, .appearance, .launchAtLogin])

        // Verify Privacy & data rows
        let privacyRows = SettingsSectionID.privacyData.rows
        #expect(privacyRows == [.saveHistory, .restoreClipboard, .clearHistory])

        // Verify Advanced rows
        let advancedRows = SettingsSectionID.advanced.rows
        #expect(advancedRows == [.typingSpeed, .resetSettings])

        // Total rows count = 20
        let totalRows = allSections.flatMap(\.rows)
        #expect(totalRows.count == 20)
    }

    @Test("Search index: empty query returns all rows")
    func emptyQueryReturnsAllRows() {
        for section in SettingsSectionID.allCases {
            let visible = SettingsSearchIndex.visibleRows(for: section, query: "")
            #expect(visible == section.rows)
        }
    }

    @Test("Search index: section title match returns all rows of that section")
    func sectionTitleMatch() {
        let privacyVisible = SettingsSearchIndex.visibleRows(for: .privacyData, query: "privacy")
        #expect(privacyVisible == SettingsSectionID.privacyData.rows)

        let cleanupVisible = SettingsSearchIndex.visibleRows(for: .textCleanup, query: "cleanup")
        #expect(cleanupVisible == SettingsSectionID.textCleanup.rows)
    }

    @Test("Search index: legacy alias terms match corresponding settings")
    func legacyAliases() {
        // "sound feedback" -> Recording sounds
        let soundRows = SettingsSearchIndex.visibleRows(for: .dictationAudio, query: "sound feedback")
        #expect(soundRows.contains(.recordingSounds))

        // "recognition language" -> Transcription language
        let langRows = SettingsSearchIndex.visibleRows(for: .dictationAudio, query: "recognition language")
        #expect(langRows.contains(.transcriptionLanguage))

        // "preserve clipboard" -> Restore clipboard
        let clipRows = SettingsSearchIndex.visibleRows(for: .privacyData, query: "preserve clipboard")
        #expect(clipRows.contains(.restoreClipboard))

        // "WPM" -> Typing speed
        let wpmRows = SettingsSearchIndex.visibleRows(for: .advanced, query: "WPM")
        #expect(wpmRows.contains(.typingSpeed))

        // "Apple Foundation Model" -> Smart cleanup
        let aiRows = SettingsSearchIndex.visibleRows(for: .textCleanup, query: "Apple Foundation Model")
        #expect(aiRows.contains(.smartCleanup))
    }

    @Test("Search index: advanced row matches reveal advanced section")
    func advancedSearchReveals() {
        let advRows = SettingsSearchIndex.visibleRows(for: .advanced, query: "typing speed")
        #expect(advRows.contains(.typingSpeed))

        let nonAdvRows = SettingsSearchIndex.visibleRows(for: .dictationAudio, query: "typing speed")
        #expect(nonAdvRows.isEmpty)
    }

    @Test("Search index: non-matching query produces empty results")
    func nonMatchingQuery() {
        for section in SettingsSectionID.allCases {
            let visible = SettingsSearchIndex.visibleRows(for: section, query: "xyznonexistentquery123")
            #expect(visible.isEmpty)
        }
    }

    @Test("Settings reset restores default Murmur preferences")
    @MainActor
    func resetToDefaults() {
        let settings = Settings.shared

        // Set non-default values
        settings.typingWPM = 99
        settings.displayName = "Test User"
        settings.cleanupEnabled = false
        settings.soundEnabled = false

        // Call reset
        settings.resetToDefaults()

        // Verify restoration of default values
        #expect(settings.typingWPM == 40)
        #expect(settings.displayName == "")
        #expect(settings.cleanupEnabled == true)
        #expect(settings.soundEnabled == true)
        #expect(settings.recordingMode == .holdToTalk)
        #expect(settings.appearanceMode == .system)
        #expect(settings.selectedMicrophoneID == "system_default")
        #expect(settings.selectedLanguage == "en-US")
    }

    @Test("AudioTapProcessor executes safely on a non-MainActor background audio queue")
    func audioTapProcessorRunsOffMainActor() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        #expect(AudioTapProcessor.isValidFormat(format))

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<1024 {
                channel[i] = 0.25 * sin(Float(i) * 0.1)
            }
        }

        // Execute on a custom background queue simulating RealtimeMessenger.mServiceQueue
        nonisolated(unsafe) let sendableBuffer = buffer
        let computedLevel: Float = await withCheckedContinuation { continuation in
            let audioQueue = DispatchQueue(label: "test.realtime.messenger.queue")
            audioQueue.async {
                let level = AudioTapProcessor.computeNormalizedLevel(from: sendableBuffer)
                continuation.resume(returning: level)
            }
        }

        #expect(computedLevel > 0.5)
        #expect(computedLevel <= 1.0)
    }

    @Test("MeterUpdateGate coalesces updates to ~24 Hz and rejects stale generations")
    func meterUpdateGateThrottlingAndGenerationSafety() {
        let gate = MeterUpdateGate()
        gate.activate(generation: 1)

        // First buffer at t=1.0s emits immediately
        let first = gate.recordAndShouldEmit(rawLevel: 0.4, generation: 1, now: 1.000)
        #expect(first != nil)
        #expect(abs((first ?? 0) - 0.4) < 1e-5)

        // Buffer 10ms later (t=1.010s) is coalesced (returns nil) but records higher peak
        let suppressed = gate.recordAndShouldEmit(rawLevel: 0.9, generation: 1, now: 1.010)
        #expect(suppressed == nil)

        // Buffer 50ms after first emission (t=1.050s) emits smoothed peak
        let second = gate.recordAndShouldEmit(rawLevel: 0.5, generation: 1, now: 1.050)
        #expect(second != nil)
        #expect((second ?? 0) > 0.6)

        // Stale generation is rejected
        let wrongGen = gate.recordAndShouldEmit(rawLevel: 0.8, generation: 999, now: 2.000)
        #expect(wrongGen == nil)

        // Deactivated gate rejects all updates
        gate.deactivate()
        let afterStop = gate.recordAndShouldEmit(rawLevel: 0.8, generation: 1, now: 3.000)
        #expect(afterStop == nil)
    }

    @Test("MicTestController start/stop idempotency and device switching while idle")
    @MainActor
    func micTestControllerIdempotencyAndIdleDeviceSwitch() {
        let micTest = MicTestController()
        #expect(!micTest.isTesting)
        #expect(micTest.level == 0)
        #expect(micTest.errorMessage == nil)

        // Starting while dictation is active must be a no-op
        micTest.startMicTest(isDictationActive: true)
        #expect(!micTest.isTesting)

        // Repeated stops when already stopped must be safe no-ops
        micTest.stopMicTest()
        micTest.stopMicTest()
        #expect(!micTest.isTesting)
        #expect(micTest.level == 0)
        #expect(micTest.errorMessage == nil)

        // Switching selected microphone while not testing must not start testing
        micTest.handleSelectedMicrophoneChange(to: "disconnected-device-uid", isDictationActive: false)
        #expect(!micTest.isTesting)

        // Hardware change notification while not testing must not start testing
        micTest.handleHardwareChange(isDictationActive: false)
        #expect(!micTest.isTesting)
    }

    @Test("CoreAudioHardware falls back gracefully when selected device UID is disconnected")
    func disconnectedDeviceFallback() {
        let allDevices = CoreAudioHardware.availableInputDevices()
        guard !allDevices.isEmpty else { return }

        let resolved = CoreAudioHardware.resolveInputDevice(for: "non-existent-disconnected-mic-uid-12345")
        if let resolved {
            #expect(resolved.didFallbackToDefault == true)
            #expect(resolved.sampleRate > 0)
            #expect(resolved.inputChannels > 0)
        }
    }
}
