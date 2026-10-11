import Testing
import Foundation
import Observation
import os
@testable import Murmur

@Suite("Murmur HUD Tests")
struct MurmurHUDTests {

    @Test("Duration formatting MM:SS and H:MM:SS")
    func durationFormatting() {
        #expect(MurmurHUDSnapshot.formatDuration(-2) == "00:00")
        #expect(MurmurHUDSnapshot.formatDuration(27) == "00:27")
        #expect(MurmurHUDSnapshot.formatDuration(59) == "00:59")
        #expect(MurmurHUDSnapshot.formatDuration(60) == "01:00")
        #expect(MurmurHUDSnapshot.formatDuration(3_599) == "59:59")
        #expect(MurmurHUDSnapshot.formatDuration(3_600) == "1:00:00")
        #expect(MurmurHUDSnapshot.formatDuration(3_661) == "1:01:01")
    }

    @Test("Snapshot level sanitization, sizing, and visibility")
    func snapshotSanitizationAndSizing() {
        let snapshot = MurmurHUDSnapshot(
            phase: .listening,
            elapsedSeconds: -1,
            levels: [Double.nan, -.infinity, -2, 0.5, 2]
        )
        #expect(snapshot.elapsedSeconds == 0)
        #expect(snapshot.levels.count == 12)
        #expect(Array(snapshot.levels.suffix(5)) == [0, 0, 0, 0.5, 1])

        let oversized = MurmurHUDSnapshot(levels: Array(repeating: 1, count: 20))
        #expect(oversized.levels.count == 12)

        #expect(!MurmurHUDSnapshot().isVisible)
        #expect(snapshot.isVisible)
        #expect(MurmurHUDSnapshot(phase: .failed).pillWidth == Double(DS.HUD.errorWidth))
        #expect(MurmurHUDSnapshot(phase: .noSpeech).pillWidth == Double(DS.HUD.messageWidth))
        #expect(MurmurHUDSnapshot(phase: .listening, elapsedSeconds: 3_599).pillWidth == Double(DS.HUD.compactWidth))
        #expect(MurmurHUDSnapshot(phase: .listening, elapsedSeconds: 3_600).pillWidth == Double(DS.HUD.compactWidth))
        #expect(MurmurHUDSnapshot(phase: .completed(.copied)).phase.accessibilityTitle == "Copied")
        #expect(MurmurHUDSnapshot(phase: .noSpeech).phase.accessibilityTitle == "No speech detected")
        #expect(MurmurHUDSnapshot(phase: .failed).phase.accessibilityTitle == "Couldn't transcribe")
    }

    @Test("Waveform buffer RMS normalization")
    func waveformRMSNormalization() {
        #expect(MurmurHUDWaveformBuffer.normalizeLinearRMS(0) == 0)
        #expect(MurmurHUDWaveformBuffer.normalizeLinearRMS(.nan) == 0)
        #expect(MurmurHUDWaveformBuffer.normalizeLinearRMS(.infinity) == 0)
        #expect(MurmurHUDWaveformBuffer.normalizeLinearRMS(1) == 1)
        #expect(abs(MurmurHUDWaveformBuffer.normalizeLinearRMS(0.001)) < 1e-9)
        #expect(abs(MurmurHUDWaveformBuffer.normalizeLinearRMS(0.01) - 1.0/3) < 1e-9)
    }

    @Test("Waveform buffer attack, decay, and reset")
    func waveformAttackDecayReset() {
        var waveform = MurmurHUDWaveformBuffer()
        waveform.append(normalizedLevel: 1)
        #expect(waveform.levels.count == 12)
        #expect(abs(waveform.levels.last! - 0.55) < 1e-9)

        for _ in 0..<200 { waveform.append(normalizedLevel: 0) }
        #expect(waveform.levels.allSatisfy { $0 < 1e-12 })

        waveform.reset()
        #expect(waveform.levels == Array(repeating: 0, count: 12))
    }

    @Test("Presentation adapter session isolation prevents stale session override")
    @MainActor
    func sessionIsolation() async {
        let adapter = HUDPresentationAdapter()
        let session1 = UUID()
        let session2 = UUID()

        adapter.sessionDidStart(sessionID: session1)
        #expect(adapter.currentSessionID == session1)
        #expect(adapter.snapshot.phase == .starting)

        // Session 2 starts while session 1 was preparing
        adapter.sessionDidStart(sessionID: session2)
        #expect(adapter.currentSessionID == session2)

        // Late event from session 1 should be completely ignored
        adapter.sessionDidBeginListening(sessionID: session1) { 0.8 }
        #expect(adapter.snapshot.phase == .starting) // Still starting session 2

        adapter.sessionDidComplete(sessionID: session1, outcome: .inserted)
        #expect(adapter.snapshot.phase == .starting) // Not overwritten by session 1

        adapter.sessionDidFail(sessionID: session1, message: "Stale failure")
        #expect(adapter.snapshot.phase == .starting) // Not overwritten by session 1 failure

        // Legitimate event from session 2 updates snapshot
        adapter.sessionDidBeginListening(sessionID: session2) { 0.5 }
        #expect(adapter.snapshot.phase == .listening)

        adapter.sessionDidBeginTranscribing(sessionID: session2)
        #expect(adapter.snapshot.phase == .transcribing)

        adapter.sessionDidBeginDelivering(sessionID: session2)
        #expect(adapter.snapshot.phase == .delivering)

        adapter.sessionDidComplete(sessionID: session2, outcome: .inserted)
        #expect(adapter.snapshot.phase == .completed(.inserted))
    }

    @Test("Outcome mapping produces exact labels")
    func outcomeMapping() {
        #expect(MurmurHUDOutcome.inserted.rawValue == "Inserted")
        #expect(MurmurHUDOutcome.copied.rawValue == "Copied")
        #expect(MurmurHUDOutcome.saved.rawValue == "Saved")
        #expect(MurmurHUDOutcome.transcribed.rawValue == "Transcribed")
    }

    @Test("Meter and phase updates do not trigger window visibility changes")
    @MainActor
    func visibilityObservation() async throws {
        let adapter = HUDPresentationAdapter()
        let session = UUID()
        adapter.sessionDidStart(sessionID: session)
        #expect(adapter.isVisible)
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = adapter.isVisible
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        adapter.sessionDidBeginListening(sessionID: session) { 0.5 }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while adapter.snapshot.levels.last == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(adapter.snapshot.levels.last! > 0)
        adapter.sessionDidBeginTranscribing(sessionID: session)
        adapter.sessionDidBeginDelivering(sessionID: session)
        adapter.sessionDidComplete(sessionID: session, outcome: .inserted)
        #expect(changes.withLock { $0 } == 0)
        adapter.sessionDidCancel(sessionID: session)
        #expect(changes.withLock { $0 } == 1)
        #expect(!adapter.isVisible)
    }
}
