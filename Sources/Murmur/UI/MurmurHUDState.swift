import Foundation
import SwiftUI

/// A presentation snapshot, NOT a recorder or a second dictation state machine.
/// The existing dictation controller creates this from confirmed engine events.
enum MurmurHUDOutcome: String, Equatable, Sendable {
    case inserted = "Inserted"
    case copied = "Copied"
    case saved = "Saved"
    case transcribed = "Transcribed"
}

enum MurmurHUDPhase: Equatable, Sendable {
    case hidden
    case starting
    case listening
    case transcribing
    case cleaning
    case delivering
    case completed(MurmurHUDOutcome)
    case noSpeech
    case failed

    var accessibilityTitle: String {
        switch self {
        case .hidden: return ""
        case .starting: return "Starting microphone"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .cleaning: return "Cleaning up"
        case .delivering: return "Inserting text"
        case .completed(let outcome): return outcome.rawValue
        case .noSpeech: return "No speech detected"
        case .failed: return "Couldn't transcribe"
        }
    }
}

struct MurmurHUDSnapshot: Equatable, Sendable {
    let sessionID: UUID?
    let phase: MurmurHUDPhase
    let elapsedSeconds: Int
    let levels: [Double]
    let errorMessage: String?
    let liveText: String

    init(
        sessionID: UUID? = nil,
        phase: MurmurHUDPhase = .hidden,
        elapsedSeconds: Int = 0,
        levels: [Double] = [],
        errorMessage: String? = nil,
        liveText: String = ""
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.elapsedSeconds = max(0, elapsedSeconds)
        let sanitized = levels.suffix(DS.HUD.waveformBarCount).map { value in
            value.isFinite ? min(1, max(0, value)) : 0
        }
        self.levels = Array(
            repeating: 0,
            count: DS.HUD.waveformBarCount - sanitized.count
        ) + sanitized
        self.errorMessage = errorMessage
        self.liveText = String(liveText.suffix(160))
    }

    var isVisible: Bool { phase != .hidden }

    /// Visible capsule dimensions, measured in macOS points, not screen pixels.
    var pillWidth: Double {
        switch phase {
        case .listening where !liveText.isEmpty:
            return 440
        case .cleaning:
            return Double(DS.HUD.messageWidth)
        case .failed:
            return Double(DS.HUD.errorWidth)
        case .noSpeech:
            return Double(DS.HUD.messageWidth)
        default:
            return Double(DS.HUD.compactWidth)
        }
    }

    static let pillHeight = Double(DS.HUD.height)

    var contentSize: CGSize {
        CGSize(width: CGFloat(pillWidth), height: DS.HUD.height)
    }

    var timerText: String {
        Self.formatDuration(elapsedSeconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        let mm = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let ss = remainder < 10 ? "0\(remainder)" : "\(remainder)"
        return hours > 0 ? "\(hours):\(mm):\(ss)" : "\(mm):\(ss)"
    }
}

/// Feed at most 20 times/second from a coalesced meter stream, not per sample.
/// This is a short audio-level history, NOT an FFT/frequency spectrum.
struct MurmurHUDWaveformBuffer {
    private(set) var levels = Array(repeating: 0.0, count: DS.HUD.waveformBarCount)
    private var smoothedLevel = 0.0

    mutating func reset() {
        levels = Array(repeating: 0.0, count: DS.HUD.waveformBarCount)
        smoothedLevel = 0
    }

    mutating func append(normalizedLevel: Double) {
        let value = normalizedLevel.isFinite
            ? min(1, max(0, normalizedLevel)) : 0
        let coefficient = value > smoothedLevel ? 0.55 : 0.20
        smoothedLevel += coefficient * (value - smoothedLevel)
        levels.removeFirst()
        levels.append(smoothedLevel)
    }

    /// Use only when the existing meter exposes linear RMS, not normalized 0...1.
    /// Display mapping: -60 dBFS = 0, 0 dBFS = 1. This does NOT alter audio.
    static func normalizeLinearRMS(_ rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let dBFS = 20 * log10(max(rms, 1e-9))
        return min(1, max(0, (dBFS + 60) / 60))
    }
}
