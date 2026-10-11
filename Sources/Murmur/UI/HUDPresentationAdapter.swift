import Foundation
import Observation

/// MainActor presentation adapter that manages MurmurHUDSnapshot lifecycle and session safety.
///
/// Ensures meter updates coalesce to at most 20 Hz, durations derive from actual monotonic capture time,
/// completions and dismissals are guarded by session ID, and delayed dismissals adhere to the contract:
/// - Success: 0.9s
/// - No speech: 1.6s
/// - Error: 4.0s or manual dismissal
@MainActor
@Observable
final class HUDPresentationAdapter {
    private(set) var snapshot: MurmurHUDSnapshot = MurmurHUDSnapshot(phase: .hidden) {
        didSet {
            if isVisible != snapshot.isVisible {
                isVisible = snapshot.isVisible
            }
        }
    }
    /// A separate observation boundary: level changes must not trigger window presentation.
    private(set) var isVisible = false

    private(set) var currentSessionID: UUID?
    private var dismissTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var captureStartTime: ContinuousClock.Instant?
    private var frozenDurationSeconds: Int = 0
    private var liveText = ""
    private var waveformBuffer = MurmurHUDWaveformBuffer()

    var onStop: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onFrameChange: ((_ contentSize: CGSize) -> Void)?

    func sessionDidStart(sessionID: UUID) {
        dismissTask?.cancel()
        dismissTask = nil
        timerTask?.cancel()
        timerTask = nil

        currentSessionID = sessionID
        captureStartTime = nil
        frozenDurationSeconds = 0
        waveformBuffer.reset()
        liveText = ""

        snapshot = MurmurHUDSnapshot(
            sessionID: sessionID,
            phase: .starting,
            elapsedSeconds: 0,
            levels: waveformBuffer.levels
        )
        onFrameChange?(snapshot.contentSize)
    }

    func sessionDidBeginListening(
        sessionID: UUID,
        getLatestLevel: @escaping @Sendable () -> Float
    ) {
        guard currentSessionID == sessionID else { return }

        let now = ContinuousClock.now
        captureStartTime = now
        frozenDurationSeconds = 0

        snapshot = MurmurHUDSnapshot(
            sessionID: sessionID,
            phase: .listening,
            elapsedSeconds: 0,
            levels: waveformBuffer.levels
        )
        onFrameChange?(snapshot.contentSize)

        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50)) // 20 Hz
                guard !Task.isCancelled, self.currentSessionID == sessionID else { break }

                let rawLevel = Double(getLatestLevel())
                self.waveformBuffer.append(normalizedLevel: rawLevel)

                if let start = self.captureStartTime {
                    let elapsed = max(0, Int(start.duration(to: .now).components.seconds))
                    self.frozenDurationSeconds = elapsed
                }

                let previousWidth = self.snapshot.pillWidth
                self.snapshot = MurmurHUDSnapshot(
                    sessionID: sessionID,
                    phase: .listening,
                    elapsedSeconds: self.frozenDurationSeconds,
                    levels: self.waveformBuffer.levels,
                    liveText: self.liveText
                )

                if self.snapshot.pillWidth != previousWidth {
                    self.onFrameChange?(self.snapshot.contentSize)
                }
            }
        }
    }

    func sessionDidUpdateTranscript(sessionID: UUID, text: String) {
        guard currentSessionID == sessionID, snapshot.phase == .listening else { return }
        liveText = text
    }

    func sessionDidBeginCleaning(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        timerTask?.cancel()
        snapshot = MurmurHUDSnapshot(sessionID: sessionID, phase: .cleaning,
                                     elapsedSeconds: frozenDurationSeconds, levels: waveformBuffer.levels)
        onFrameChange?(snapshot.contentSize)
    }

    func sessionDidBeginTranscribing(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        timerTask?.cancel()
        timerTask = nil

        snapshot = MurmurHUDSnapshot(
            sessionID: sessionID,
            phase: .transcribing,
            elapsedSeconds: frozenDurationSeconds
        )
        onFrameChange?(snapshot.contentSize)
    }

    func sessionDidBeginDelivering(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }

        snapshot = MurmurHUDSnapshot(
            sessionID: sessionID,
            phase: .delivering,
            elapsedSeconds: frozenDurationSeconds
        )
        onFrameChange?(snapshot.contentSize)
    }

    func sessionDidComplete(
        sessionID: UUID,
        outcome: MurmurHUDOutcome?,
        isNoSpeech: Bool = false
    ) {
        guard currentSessionID == sessionID else { return }
        timerTask?.cancel()
        timerTask = nil

        if isNoSpeech {
            snapshot = MurmurHUDSnapshot(
                sessionID: sessionID,
                phase: .noSpeech,
                elapsedSeconds: frozenDurationSeconds
            )
            onFrameChange?(snapshot.contentSize)
            scheduleDismissal(sessionID: sessionID, after: .milliseconds(1600))
        } else if let outcome {
            snapshot = MurmurHUDSnapshot(
                sessionID: sessionID,
                phase: .completed(outcome),
                elapsedSeconds: frozenDurationSeconds
            )
            onFrameChange?(snapshot.contentSize)
            scheduleDismissal(sessionID: sessionID, after: .milliseconds(900))
        } else {
            snapshot = MurmurHUDSnapshot(sessionID: sessionID, phase: .hidden)
            onFrameChange?(snapshot.contentSize)
        }
    }

    func sessionDidFail(sessionID: UUID, message: String) {
        guard currentSessionID == sessionID else { return }
        timerTask?.cancel()
        timerTask = nil

        snapshot = MurmurHUDSnapshot(
            sessionID: sessionID,
            phase: .failed,
            elapsedSeconds: frozenDurationSeconds,
            errorMessage: message
        )
        onFrameChange?(snapshot.contentSize)
        scheduleDismissal(sessionID: sessionID, after: .seconds(4))
    }

    func sessionDidCancel(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        timerTask?.cancel()
        timerTask = nil
        dismissTask?.cancel()
        dismissTask = nil

        snapshot = MurmurHUDSnapshot(sessionID: sessionID, phase: .hidden)
        onFrameChange?(snapshot.contentSize)
    }

    func manualDismiss(sessionID: UUID? = nil) {
        if let sessionID, currentSessionID != sessionID { return }
        dismissTask?.cancel()
        dismissTask = nil
        timerTask?.cancel()
        timerTask = nil

        snapshot = MurmurHUDSnapshot(sessionID: currentSessionID, phase: .hidden)
        onFrameChange?(snapshot.contentSize)
        onDismiss?()
    }

    private func scheduleDismissal(sessionID: UUID, after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.currentSessionID == sessionID else { return }
            self.snapshot = MurmurHUDSnapshot(sessionID: sessionID, phase: .hidden)
            self.onFrameChange?(self.snapshot.contentSize)
        }
    }
}
