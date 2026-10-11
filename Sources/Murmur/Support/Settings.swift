import Foundation
import Observation
import SwiftUI

/// Which speech engine family transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet
    case whisper

    var displayName: String {
        switch self {
        case .apple: "Apple Speech"
        case .parakeet: "Parakeet TDT"
        case .whisper: "Whisper"
        }
    }

    var showsLiveText: Bool { true }
}

enum WritingEngineChoice: String, CaseIterable, Sendable {
    case apple, qwen, rules
    var displayName: String {
        switch self { case .apple: "Apple Intelligence"; case .qwen: "Qwen (local)"; case .rules: "Rules only" }
    }
}

/// Formatting and cleanup pass selection.
enum CleanupMode: String, CaseIterable, Sendable {
    case smart
    case basic
    case off

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .basic: "Basic"
        case .off: "Off"
        }
    }
}

/// Appearance mode choice.
enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case dark
    case light

    var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Dictation recording mode.
enum RecordingMode: String, CaseIterable, Sendable {
    case holdToTalk
    case toggle

    var displayName: String {
        switch self {
        case .holdToTalk: "Hold to Talk"
        case .toggle: "Press to Toggle"
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var shortcut: ShortcutBinding {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Keys.shortcutData)
            }
        }
    }

    /// Backward compatibility bridge for PushToTalkKey
    var pushToTalkKey: PushToTalkKey {
        get {
            if shortcut == .fn { return .fn }
            if shortcut == .rightCommand { return .rightCommand }
            return .rightOption
        }
        set {
            shortcut = newValue.asBinding
        }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// Specific model ID chosen in the Voice Models manager.
    var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Keys.selectedModelID) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    var writingEngine: WritingEngineChoice {
        didSet { defaults.set(writingEngine.rawValue, forKey: "writingEngine") }
    }
    var livePreview: Bool {
        didSet { defaults.set(livePreview, forKey: "livePreview") }
    }
    var showPill: Bool {
        didSet { defaults.set(showPill, forKey: "showPill") }
    }
    var writingAssistantEnabled: Bool {
        didSet { defaults.set(writingAssistantEnabled, forKey: "writingAssistantEnabled") }
    }
    var readFieldContext: Bool {
        didSet { defaults.set(readFieldContext, forKey: "readFieldContext") }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// Audio input device selection.
    var selectedMicrophoneID: String {
        didSet { defaults.set(selectedMicrophoneID, forKey: Keys.selectedMicrophoneID) }
    }

    /// Selected recognition language identifier (e.g. "en-US" or "auto").
    var selectedLanguage: String {
        didSet { defaults.set(selectedLanguage, forKey: Keys.selectedLanguage) }
    }

    /// Optional user display name for Dashboard greeting.
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.displayName) }
    }

    /// Appearance theme (System, Light, Dark).
    var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    /// Recording interaction mode.
    var recordingMode: RecordingMode {
        didSet { defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode) }
    }

    /// Assumed user typing speed (Words Per Minute) for time-saved calculation.
    var typingWPM: Int {
        didSet { defaults.set(typingWPM, forKey: Keys.typingWPM) }
    }

    /// Whether history is persisted.
    var saveHistory: Bool {
        didSet { defaults.set(saveHistory, forKey: Keys.saveHistory) }
    }

    /// History retention days (0 = forever, 30, 90, 365).
    var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) }
    }

    /// Preserve and restore previous clipboard contents after pasteboard injection.
    var preserveClipboard: Bool {
        didSet { defaults.set(preserveClipboard, forKey: Keys.preserveClipboard) }
    }

    /// Sidebar collapsed state.
    var sidebarCollapsed: Bool {
        didSet { defaults.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed) }
    }

    /// Dedicated file transcription model ID. Kept separate from global push-to-talk dictation.
    var fileTranscriptionModelID: String {
        didSet { defaults.set(fileTranscriptionModelID, forKey: Keys.fileTranscriptionModelID) }
    }

    /// Dedicated file transcription language selection ("auto", "en", etc.).
    var fileTranscriptionLanguage: String {
        didSet { defaults.set(fileTranscriptionLanguage, forKey: Keys.fileTranscriptionLanguage) }
    }

    /// Writes detected Hindi or Urdu speech in Latin letters after transcription.
    var fileTranscriptionRomanScript: Bool {
        didSet { defaults.set(fileTranscriptionRomanScript, forKey: Keys.fileTranscriptionRomanScript) }
    }

    /// Dedicated file transcription cleanup choice (smart = On, off = raw transcript).
    var fileTranscriptionCleanup: CleanupMode {
        didSet { defaults.set(fileTranscriptionCleanup.rawValue, forKey: Keys.fileTranscriptionCleanup) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let shortcutData = "shortcutData"
        static let pushToTalkKey = "pushToTalkKey"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let engine = "engine"
        static let selectedModelID = "selectedModelID"
        static let smartCleanup = "smartCleanup"
        static let selectedMicrophoneID = "selectedMicrophoneID"
        static let selectedLanguage = "selectedLanguage"
        static let displayName = "displayName"
        static let appearanceMode = "appearanceMode"
        static let recordingMode = "recordingMode"
        static let typingWPM = "typingWPM"
        static let saveHistory = "saveHistory"
        static let historyRetentionDays = "historyRetentionDays"
        static let preserveClipboard = "preserveClipboard"
        static let sidebarCollapsed = "sidebarCollapsed"
        static let fileTranscriptionModelID = "fileTranscriptionModelID"
        static let fileTranscriptionLanguage = "fileTranscriptionLanguage"
        static let fileTranscriptionRomanScript = "fileTranscriptionRomanScript"
        static let fileTranscriptionCleanup = "fileTranscriptionCleanup"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.shortcutData),
           let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            shortcut = decoded
        } else {
            let legacyKey = defaults.string(forKey: Keys.pushToTalkKey)
            let migrated = ShortcutBinding.migrate(from: legacyKey)
            shortcut = migrated
            if let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: Keys.shortcutData)
            }
        }

        // Apple by default: no download, no dependency, live text while speaking.
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        selectedModelID = defaults.string(forKey: Keys.selectedModelID) ?? "apple-speech"
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? false
        writingEngine = WritingEngineChoice(rawValue: defaults.string(forKey: "writingEngine") ?? "apple") ?? .apple
        livePreview = defaults.object(forKey: "livePreview") as? Bool ?? true
        showPill = defaults.object(forKey: "showPill") as? Bool ?? true
        writingAssistantEnabled = defaults.object(forKey: "writingAssistantEnabled") as? Bool ?? true
        readFieldContext = defaults.object(forKey: "readFieldContext") as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true

        selectedMicrophoneID = defaults.string(forKey: Keys.selectedMicrophoneID) ?? "system_default"
        selectedLanguage = defaults.string(forKey: Keys.selectedLanguage) ?? "en-US"
        displayName = defaults.string(forKey: Keys.displayName) ?? ""

        let rawAppearance = defaults.string(forKey: Keys.appearanceMode) ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: rawAppearance) ?? .system

        let rawRecMode = defaults.string(forKey: Keys.recordingMode) ?? RecordingMode.holdToTalk.rawValue
        recordingMode = RecordingMode(rawValue: rawRecMode) ?? .holdToTalk

        typingWPM = defaults.object(forKey: Keys.typingWPM) as? Int ?? 40
        saveHistory = defaults.object(forKey: Keys.saveHistory) as? Bool ?? true
        historyRetentionDays = defaults.object(forKey: Keys.historyRetentionDays) as? Int ?? 0
        preserveClipboard = defaults.object(forKey: Keys.preserveClipboard) as? Bool ?? true
        sidebarCollapsed = defaults.object(forKey: Keys.sidebarCollapsed) as? Bool ?? false

        fileTranscriptionModelID = defaults.string(forKey: Keys.fileTranscriptionModelID) ?? "whisper-large-v3"
        fileTranscriptionLanguage = defaults.string(forKey: Keys.fileTranscriptionLanguage) ?? "auto"
        fileTranscriptionRomanScript = defaults.bool(forKey: Keys.fileTranscriptionRomanScript)
        let rawCleanup = defaults.string(forKey: Keys.fileTranscriptionCleanup) ?? CleanupMode.smart.rawValue
        fileTranscriptionCleanup = rawCleanup == CleanupMode.off.rawValue ? .off : .smart
    }

    /// Resets only Murmur's preference keys to default values without deleting history, dictionary, or models.
    func resetToDefaults() {
        shortcut = .defaultBinding
        engine = .apple
        selectedModelID = "apple-speech"
        cleanupEnabled = true
        smartCleanup = false
        writingEngine = .apple
        livePreview = true
        showPill = true
        writingAssistantEnabled = true
        readFieldContext = false
        soundEnabled = true
        selectedMicrophoneID = "system_default"
        selectedLanguage = "en-US"
        displayName = ""
        appearanceMode = .system
        recordingMode = .holdToTalk
        typingWPM = 40
        saveHistory = true
        historyRetentionDays = 0
        preserveClipboard = true
        sidebarCollapsed = false
        fileTranscriptionModelID = "whisper-large-v3"
        fileTranscriptionLanguage = "auto"
        fileTranscriptionRomanScript = false
        fileTranscriptionCleanup = .smart
    }
}
