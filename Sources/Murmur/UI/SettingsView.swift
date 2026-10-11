import SwiftUI
import AppKit
import AVFoundation

// MARK: - Search Index & Identifiers

enum SettingsRowID: String, CaseIterable, Hashable, Identifiable {
    case shortcut
    case recordingMode
    case microphone
    case transcriptionLanguage
    case recordingSounds
    case automaticFormatting
    case smartCleanup
    case writingEngine
    case livePreview
    case floatingPill
    case fieldContext
    case writingAssistant
    case launchAtLogin
    case displayName
    case appearance
    case saveHistory
    case restoreClipboard
    case clearHistory
    case typingSpeed
    case resetSettings

    var id: String { rawValue }
}

enum SettingsSectionID: String, CaseIterable, Hashable, Identifiable {
    case dictationAudio = "Dictation & audio"
    case textCleanup = "Text cleanup"
    case personalization = "Personalization"
    case privacyData = "Privacy & data"
    case advanced = "Advanced"

    var id: String { rawValue }
    var title: String { rawValue }

    var lucide: LucideIcon.Name {
        switch self {
        case .dictationAudio: return .mic
        case .textCleanup: return .fileText
        case .personalization: return .userRound
        case .privacyData: return .shield
        case .advanced: return .slidersHorizontal
        }
    }

    var rows: [SettingsRowID] {
        switch self {
        case .dictationAudio:
            return [.shortcut, .recordingMode, .microphone, .transcriptionLanguage, .recordingSounds, .livePreview, .floatingPill]
        case .textCleanup:
            return [.automaticFormatting, .writingEngine, .smartCleanup, .fieldContext, .writingAssistant]
        case .personalization:
            return [.displayName, .appearance, .launchAtLogin]
        case .privacyData:
            return [.saveHistory, .restoreClipboard, .clearHistory]
        case .advanced:
            return [.typingSpeed, .resetSettings]
        }
    }
}

struct SettingsSearchIndex {
    struct RowMetadata {
        let title: String
        let helper: String?
        let keywords: [String]
    }

    static func metadata(for row: SettingsRowID) -> RowMetadata {
        switch row {
        case .writingAssistant:
            return RowMetadata(title: "Writing Assistant", helper: "Show writing tools beside text fields. Select text to proofread or rewrite with Qwen.", keywords: ["assistant", "sparkle", "grammar", "proofread", "rewrite", "friendly", "qwen", "selected text"])
        case .writingEngine:
            return RowMetadata(title: "Writing engine", helper: "Local cleanup and meeting summaries.", keywords: ["qwen", "models", "writing", "llm", "apple", "cleanup"])
        case .livePreview:
            return RowMetadata(title: "Live transcript", helper: "Preview words in the pill while you speak.", keywords: ["live", "preview", "streaming"])
        case .floatingPill:
            return RowMetadata(title: "Floating pill", helper: "Show recording feedback above other apps.", keywords: ["pill", "overlay", "waveform"])
        case .fieldContext:
            return RowMetadata(title: "Use nearby text", helper: "Use a small amount of text before the cursor for local cleanup.", keywords: ["context", "privacy", "field", "names"])
        case .launchAtLogin:
            return RowMetadata(title: "Launch at login", helper: "Keep Murmur ready when you sign in.", keywords: ["login", "startup", "launch"])
        case .shortcut:
            return RowMetadata(
                title: "Shortcut",
                helper: nil,
                keywords: ["shortcut", "hotkey", "binding", "key", "keycap", "trigger", "push to talk"]
            )
        case .recordingMode:
            return RowMetadata(
                title: "Recording mode",
                helper: "Hold the shortcut to record release to transcribe and insert Press to toggle",
                keywords: ["recording mode", "hold to talk", "press to toggle", "toggle", "push to talk", "interaction", "mode"]
            )
        case .microphone:
            return RowMetadata(
                title: "Microphone",
                helper: "Microphone test only",
                keywords: ["microphone", "mic", "input device", "audio input", "sound input", "sensitivity test", "test", "audio device"]
            )
        case .transcriptionLanguage:
            return RowMetadata(
                title: "Transcription language",
                helper: nil,
                keywords: ["transcription language", "recognition language", "language", "auto-detect", "english", "locale", "speech language"]
            )
        case .recordingSounds:
            return RowMetadata(
                title: "Recording sounds",
                helper: "Play sounds when dictation starts and finishes.",
                keywords: ["recording sounds", "sound feedback", "sound", "audio feedback", "chimes", "audio cues"]
            )
        case .automaticFormatting:
            return RowMetadata(
                title: "Automatic formatting",
                helper: "Punctuation, capitalization, and number formatting.",
                keywords: ["fillers", "filler words", "um", "uh", "automatic formatting", "text formatting", "punctuation", "capitalization", "number formatting", "cleanup"]
            )
        case .smartCleanup:
            return RowMetadata(
                title: "Smart cleanup",
                helper: "Improve sentence structure and spoken corrections on your Mac.",
                keywords: ["smart cleanup", "apple foundation model", "apple intelligence", "sentence structure", "spoken corrections", "ai", "llm", "foundation model"]
            )
        case .displayName:
            return RowMetadata(
                title: "Display name",
                helper: "Used for your Dashboard greeting.",
                keywords: ["display name", "name", "greeting", "profile", "dashboard greeting"]
            )
        case .appearance:
            return RowMetadata(
                title: "Appearance",
                helper: nil,
                keywords: ["appearance", "theme", "dark", "light", "system", "color scheme", "mode"]
            )
        case .saveHistory:
            return RowMetadata(
                title: "Save transcription history",
                helper: "Keep transcripts on this Mac.",
                keywords: ["save transcription history", "history", "save history", "transcripts", "retention", "storage", "local"]
            )
        case .restoreClipboard:
            return RowMetadata(
                title: "Restore clipboard",
                helper: "Restore what you copied before text insertion.",
                keywords: ["restore clipboard", "preserve clipboard", "clipboard", "pasteboard", "copy", "restore"]
            )
        case .clearHistory:
            return RowMetadata(
                title: "Clear saved history",
                helper: "Permanently delete saved transcription records.",
                keywords: ["clear saved history", "clear history", "delete history", "trash", "purge", "remove transcripts"]
            )
        case .typingSpeed:
            return RowMetadata(
                title: "Typing speed",
                helper: "Used to estimate time saved on your Dashboard.",
                keywords: ["typing speed", "wpm", "words per minute", "words/min", "speed", "time saved", "baseline"]
            )
        case .resetSettings:
            return RowMetadata(
                title: "Reset settings",
                helper: "Restore default preferences. Keep history and dictionary.",
                keywords: ["reset settings", "reset all preferences", "defaults", "factory reset", "restore defaults"]
            )
        }
    }

    static func matches(row: SettingsRowID, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }

        let item = metadata(for: row)
        if item.title.lowercased().contains(q) { return true }
        if let helper = item.helper, helper.lowercased().contains(q) { return true }
        if item.keywords.contains(where: { $0.contains(q) || q.contains($0) }) { return true }
        return false
    }

    static func visibleRows(for section: SettingsSectionID, query: String) -> [SettingsRowID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return section.rows }

        // When a section title matches, show all its rows
        if section.title.lowercased().contains(q) {
            return section.rows
        }

        // Otherwise, show matching rows in this section
        return section.rows.filter { matches(row: $0, query: q) }
    }
}

// MARK: - Main Settings View

/// The unified, vertically scrollable Settings view for Murmur.
///
/// Implements the redesigned single-page structure:
/// 1. Persistent page header with title, subtitle, and search field
/// 2. One vertical ScrollView with four open sections and one collapsible Advanced section
/// 3. Real preference bindings and audio test engine
struct SettingsView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var deviceManager = AudioDeviceManager.shared

    // Navigation & Presentation State
    @State private var searchQuery: String = ""
    @State private var isAdvancedUserExpanded: Bool = false
    @State private var isShowingShortcutPicker: Bool = false
    @State private var isConfirmingClearHistory: Bool = false
    @State private var isConfirmingReset: Bool = false

    // Field Drafts & Validation
    @State private var displayNameDraft: String = ""
    @State private var typingWPMText: String = ""
    @State private var wpmError: String? = nil

    // In-App Microphone Test Controller
    @State private var micTest = MicTestController()

    private var isTestingMic: Bool { micTest.isTesting }
    private var micTestLevel: Float { micTest.level }
    private var micTestError: String? { micTest.errorMessage }

    init(controller: DictationController) {
        self.controller = controller
    }

    private var hasSavedHistory: Bool {
        !RunStore.shared.runs.isEmpty
    }

    private var isAdvancedEffectiveExpanded: Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Temporarily reveal if advanced contains matches
            return !SettingsSearchIndex.visibleRows(for: .advanced, query: trimmed).isEmpty
        }
        return isAdvancedUserExpanded
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width < DS.Layout.settingsCompactBreakpoint {
            return DS.Space.roomy
        }
        if width < DS.Layout.settingsWideBreakpoint {
            return DS.Space.wide
        }
        return DS.Space.panel
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let isCompact = availableWidth < DS.Layout.settingsCompactBreakpoint
            let hPadding = horizontalPadding(for: availableWidth)

            VStack(alignment: .leading, spacing: 0) {
                // Persistent Page Header
                SettingsHeader(
                    searchQuery: $searchQuery,
                    isCompact: isCompact
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, hPadding)
                .padding(.top, isCompact ? DS.Space.card : DS.Space.panel)
                .padding(.bottom, DS.Space.wide)

                // Single Vertical ScrollView
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: DS.Space.wide) {
                            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            let dictationRows = SettingsSearchIndex.visibleRows(for: .dictationAudio, query: query)
                            let cleanupRows = SettingsSearchIndex.visibleRows(for: .textCleanup, query: query)
                            let personalizationRows = SettingsSearchIndex.visibleRows(for: .personalization, query: query)
                            let privacyRows = SettingsSearchIndex.visibleRows(for: .privacyData, query: query)
                            let advancedRows = SettingsSearchIndex.visibleRows(for: .advanced, query: query)

                            let hasAnyMatches = !dictationRows.isEmpty || !cleanupRows.isEmpty ||
                                !personalizationRows.isEmpty || !privacyRows.isEmpty || !advancedRows.isEmpty

                            if hasAnyMatches {
                                // 1. Dictation & Audio (Open)
                                if !dictationRows.isEmpty {
                                    dictationAudioSection(visibleRows: dictationRows, isCompact: isCompact)
                                        .id("dictationAudio")
                                }

                                // 2. Text Cleanup (Open)
                                if !cleanupRows.isEmpty {
                                    textCleanupSection(visibleRows: cleanupRows, isCompact: isCompact)
                                        .id("textCleanup")
                                }

                                // 3. Personalization (Open)
                                if !personalizationRows.isEmpty {
                                    personalizationSection(visibleRows: personalizationRows, isCompact: isCompact)
                                        .id("personalization")
                                }

                                // 4. Privacy & Data (Open)
                                if !privacyRows.isEmpty {
                                    privacyDataSection(visibleRows: privacyRows, isCompact: isCompact)
                                        .id("privacyData")
                                }

                                // 5. Advanced (Collapsed initially)
                                if !advancedRows.isEmpty {
                                    advancedSection(visibleRows: advancedRows, isCompact: isCompact)
                                        .id("advanced")
                                }

                                Color.clear.frame(height: 1).id("bottom")
                            } else {
                                // Empty Search State
                                emptySearchState
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, hPadding)
                        .padding(.bottom, DS.Space.generous)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("murmurSettingsScroll"))) { notif in
                        if let target = notif.object as? String {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(target, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(DS.Color.canvas)
        .sheet(isPresented: $isShowingShortcutPicker) {
            ShortcutRecorderSheet(controller: controller)
        }
        .confirmationDialog(
            "Delete all saved transcription history?",
            isPresented: $isConfirmingClearHistory,
            titleVisibility: .visible
        ) {
            Button("Delete history", role: .destructive) {
                RunLog.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes saved transcription records and cannot be undone.")
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset settings", role: .destructive) {
                settings.resetToDefaults()
                controller.reloadHotkey()
                displayNameDraft = settings.displayName
                typingWPMText = String(settings.typingWPM)
                wpmError = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore Murmur’s default preferences? Saved transcription history, dictionary entries, and downloaded models will be kept.")
        }
        .onAppear {
            displayNameDraft = settings.displayName
            typingWPMText = String(settings.typingWPM)
            deviceManager.refreshDevices()
        }
        .onDisappear {
            stopMicTest()
        }
        .onChange(of: searchQuery) { _, newQuery in
            if (isTestingMic || micTestError != nil) && !SettingsSearchIndex.visibleRows(for: .dictationAudio, query: newQuery).contains(.microphone) {
                stopMicTest()
            }
        }
        .onChange(of: settings.selectedMicrophoneID) { _, newID in
            micTest.handleSelectedMicrophoneChange(to: newID, isDictationActive: controller.state.isActive)
        }
        .onChange(of: deviceManager.hardwareChangeRevision) { _, _ in
            micTest.handleHardwareChange(isDictationActive: controller.state.isActive)
        }
        .onChange(of: controller.state.isActive) { _, isActive in
            if isActive {
                stopMicTest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("murmurSettingsSearch"))) { notif in
            if let q = notif.object as? String {
                searchQuery = q
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("murmurSettingsExpandAdvanced"))) { notif in
            if let exp = notif.object as? Bool {
                isAdvancedUserExpanded = exp
            }
        }
    }

    // MARK: - Section 1: Dictation & Audio

    @ViewBuilder
    private func dictationAudioSection(visibleRows: [SettingsRowID], isCompact: Bool) -> some View {
        SettingsSectionSurface(
            icon: .mic,
            title: "Dictation & audio",
            isCollapsible: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider().overlay(DS.Color.borderSubtle)
                    }

                    switch row {
                    case .shortcut:
                        shortcutRow(isCompact: isCompact)
                    case .recordingMode:
                        recordingModeRow(isCompact: isCompact)
                    case .microphone:
                        microphoneRow(isCompact: isCompact)
                    case .transcriptionLanguage:
                        transcriptionLanguageRow(isCompact: isCompact)
                    case .recordingSounds:
                        recordingSoundsRow(isCompact: isCompact)
                    case .livePreview:
                        SettingsRowContainer(title: "Live transcript", helper: "Preview words in the pill while you speak. Other apps receive only the final text.", isWideControl: false, isCompact: isCompact) {
                            Toggle("Live transcript", isOn: $settings.livePreview).labelsHidden().toggleStyle(.switch)
                        }
                    case .floatingPill:
                        SettingsRowContainer(title: "Floating pill", helper: "Show dictation feedback. Meeting recording controls stay visible.", isWideControl: false, isCompact: isCompact) {
                            Toggle("Floating pill", isOn: $settings.showPill).labelsHidden().toggleStyle(.switch)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func shortcutRow(isCompact: Bool) -> some View {
        SettingsRowContainer(
            title: "Shortcut",
            isWideControl: true,
            isCompact: isCompact
        ) {
            HStack(spacing: DS.Space.snug) {
                ShortcutBadge(settings.shortcut)

                MurmurButton("Change…", style: .secondary) {
                    controller.suspendHotkey()
                    isShowingShortcutPicker = true
                }
            }
        }
    }

    private func recordingModeRow(isCompact: Bool) -> some View {
        let helperText: String = switch settings.recordingMode {
        case .holdToTalk:
            "Hold the shortcut to record; release to transcribe and insert."
        case .toggle:
            "Press the shortcut to record; press again to transcribe and insert."
        }

        return SettingsRowContainer(
            title: "Recording mode",
            helper: helperText,
            isWideControl: true,
            isCompact: isCompact
        ) {
            Picker("", selection: $settings.recordingMode) {
                Text("Hold to Talk").tag(RecordingMode.holdToTalk)
                Text("Press to Toggle").tag(RecordingMode.toggle)
            }
            .pickerStyle(.segmented)
            .frame(width: isCompact ? nil : DS.Layout.settingsPickerWidth)
        }
    }

    private func microphoneRow(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRowContainer(
                title: "Microphone",
                isWideControl: true,
                isCompact: isCompact
            ) {
                HStack(spacing: DS.Space.snug) {
                    Picker("", selection: $settings.selectedMicrophoneID) {
                        Text("System Default").tag("system_default")
                        Divider()
                        ForEach(deviceManager.devices) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                        if settings.selectedMicrophoneID != "system_default" &&
                            !deviceManager.devices.contains(where: { $0.id == settings.selectedMicrophoneID }) {
                            Text("(Unavailable) Disconnected Device").tag(settings.selectedMicrophoneID)
                        }
                    }
                    .frame(maxWidth: isCompact ? .infinity : DS.Layout.settingsDevicePickerWidth)
                    .disabled(controller.state.isActive)
                    .help(controller.state.isActive ? "Cannot change input device while recording" : "Select audio input device")

                    MurmurButton(
                        isTestingMic ? "Stop" : "Test",
                        icon: isTestingMic ? "stop.fill" : "mic.fill",
                        style: isTestingMic ? .danger : .secondary
                    ) {
                        if isTestingMic {
                            stopMicTest()
                        } else {
                            startMicTest()
                        }
                    }
                    .disabled(controller.state.isActive && !isTestingMic)
                    .help(controller.state.isActive ? "Cannot test microphone while dictation is active" : (isTestingMic ? "Stop microphone test" : "Test microphone input levels"))
                }
            }

            // Inline Test Meter (expands below Microphone row)
            if isTestingMic || micTestError != nil {
                MicrophoneTestInlineView(
                    level: micTestLevel,
                    errorMessage: micTestError,
                    onStop: { stopMicTest() }
                )
                .padding(.bottom, DS.Space.snug)
            }
        }
    }

    private func transcriptionLanguageRow(isCompact: Bool) -> some View {
        let limitationText: String? = (settings.engine == .parakeet)
            ? "Parakeet v3 supports its trained languages; v2 and 110M are English. Whisper supports broader language detection."
            : nil

        return SettingsRowContainer(
            title: "Transcription language",
            note: limitationText,
            isWideControl: true,
            isCompact: isCompact
        ) {
            Picker("", selection: $settings.selectedLanguage) {
                Text("Auto-detect").tag("auto")
                Divider()
                Text("English (United States)").tag("en-US")
                Text("English (United Kingdom)").tag("en-GB")
            }
            .frame(width: isCompact ? nil : DS.Layout.settingsFieldWidth)
        }
    }

    private func recordingSoundsRow(isCompact: Bool) -> some View {
        SettingsRowContainer(
            title: "Recording sounds",
            helper: "Play sounds when dictation starts and finishes.",
            isWideControl: false,
            isCompact: isCompact
        ) {
            Toggle("Recording sounds", isOn: $settings.soundEnabled).labelsHidden()
                .toggleStyle(.switch)
        }
    }

    // MARK: - Section 2: Text Cleanup

    @ViewBuilder
    private func textCleanupSection(visibleRows: [SettingsRowID], isCompact: Bool) -> some View {
        SettingsSectionSurface(
            icon: .fileText,
            title: "Text cleanup",
            isCollapsible: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider().overlay(DS.Color.borderSubtle)
                    }

                    switch row {
                    case .automaticFormatting:
                        SettingsRowContainer(
                            title: "Automatic formatting",
                            helper: "Punctuation, capitalization, and number formatting.",
                            isWideControl: false,
                            isCompact: isCompact
                        ) {
                            Toggle("Automatic formatting", isOn: $settings.cleanupEnabled).labelsHidden()
                                .toggleStyle(.switch)
                        }
                    case .writingEngine:
                        SettingsRowContainer(title: "Writing engine", helper: "Applies your style and context after speech recognition. Download Qwen separately in Models.", isWideControl: true, isCompact: isCompact) {
                            Picker("Writing engine", selection: $settings.writingEngine) {
                                ForEach(WritingEngineChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }.labelsHidden().frame(maxWidth: 240)
                        }
                    case .smartCleanup:
                        SettingsRowContainer(title: "Smart cleanup", helper: "Apply your writing style, memory and spoken corrections on this Mac.", note: writingReadiness, isWideControl: false, isCompact: isCompact) {
                            Toggle("Smart cleanup", isOn: $settings.smartCleanup)
                                .labelsHidden().toggleStyle(.switch).disabled(!settings.cleanupEnabled || settings.writingEngine == .rules)
                        }
                    case .writingAssistant:
                        SettingsRowContainer(title: "Writing Assistant", helper: "Show a sparkle button beside text fields to proofread, rewrite and format selected text. Uses your selected Qwen model independently of dictation cleanup. Plain text replaces the selection; rich formatting may change.", isWideControl: false, isCompact: isCompact) {
                            Toggle("Writing Assistant", isOn: $settings.writingAssistantEnabled).labelsHidden().toggleStyle(.switch)
                        }
                    case .fieldContext:
                        SettingsRowContainer(title: "Use nearby text", helper: "Read up to 240 characters before the cursor for spelling context. Secure fields are excluded; nothing leaves this Mac.", isWideControl: false, isCompact: isCompact) {
                            Toggle("Use nearby text", isOn: $settings.readFieldContext).labelsHidden().toggleStyle(.switch)
                        }
                    default:
                        EmptyView()
                    }
                }
                if visibleRows.contains(.automaticFormatting) {
                    FillerWordsSettingsView()
                }
            }
        }
    }

    private var writingReadiness: String? {
        switch settings.writingEngine {
        case .qwen:
            if !WritingModelManager.shared.runtimeAvailable { return "The writing runtime is missing from this build. Basic cleanup remains available." }
            return WritingModelManager.shared.selectedModelURL == nil ? "Choose and download a Qwen model in Models → Writing & cleanup. Basic cleanup works until it is ready." : nil
        case .apple: return FoundationModelFormatter.unavailableReason
        case .rules: return "Fast deterministic formatting; writing styles and memory require a local writing model."
        }
    }

    // MARK: - Section 3: Personalization

    @ViewBuilder
    private func personalizationSection(visibleRows: [SettingsRowID], isCompact: Bool) -> some View {
        SettingsSectionSurface(
            icon: .userRound,
            title: "Personalization",
            isCollapsible: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider().overlay(DS.Color.borderSubtle)
                    }

                    switch row {
                    case .displayName:
                        SettingsRowContainer(
                            title: "Display name",
                            isWideControl: true,
                            isCompact: isCompact
                        ) {
                            TextField("Your name", text: $displayNameDraft)
                                .textFieldStyle(.plain)
                                .settingsControlSurface()
                                .frame(width: isCompact ? nil : DS.Layout.settingsFieldWidth)
                                .help("Used for your Dashboard greeting.")
                                .accessibilityLabel("Display name, used for your Dashboard greeting")
                                .onSubmit {
                                    settings.displayName = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                        }
                    case .appearance:
                        SettingsRowContainer(
                            title: "Appearance",
                            isWideControl: true,
                            isCompact: isCompact
                        ) {
                            Picker("", selection: $settings.appearanceMode) {
                                Text("System").tag(AppearanceMode.system)
                                Text("Light").tag(AppearanceMode.light)
                                Text("Dark").tag(AppearanceMode.dark)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: isCompact ? nil : DS.Layout.settingsPickerWidth)
                        }
                    case .launchAtLogin:
                        SettingsRowContainer(title: "Launch at login", helper: "Keep Murmur ready when you sign in.", note: LoginLaunchController.shared.errorMessage, isWideControl: false, isCompact: isCompact) {
                            Toggle("Launch at login", isOn: Binding(get: { LoginLaunchController.shared.isEnabled }, set: { LoginLaunchController.shared.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Section 4: Privacy & Data

    @ViewBuilder
    private func privacyDataSection(visibleRows: [SettingsRowID], isCompact: Bool) -> some View {
        SettingsSectionSurface(
            icon: .shield,
            title: "Privacy & data",
            isCollapsible: false
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider().overlay(DS.Color.borderSubtle)
                    }

                    switch row {
                    case .saveHistory:
                        SettingsRowContainer(
                            title: "Save transcription history",
                            helper: "Keep transcripts on this Mac.",
                            isWideControl: false,
                            isCompact: isCompact
                        ) {
                            Toggle("Save transcription history", isOn: $settings.saveHistory).labelsHidden()
                                .toggleStyle(.switch)
                        }
                    case .restoreClipboard:
                        SettingsRowContainer(
                            title: "Restore clipboard",
                            helper: "Restore what you copied before text insertion.",
                            isWideControl: false,
                            isCompact: isCompact
                        ) {
                            Toggle("Restore clipboard", isOn: $settings.preserveClipboard).labelsHidden()
                                .toggleStyle(.switch)
                        }
                    case .clearHistory:
                        SettingsRowContainer(
                            title: "Clear saved history",
                            helper: "Permanently delete saved transcription records.",
                            isWideControl: true,
                            isCompact: isCompact
                        ) {
                            MurmurButton("Clear history…", lucide: .trash2, style: .secondary) {
                                isConfirmingClearHistory = true
                            }
                            .disabled(!hasSavedHistory)
                            .help(hasSavedHistory ? "Delete all stored transcription history" : "No saved history to delete")
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Advanced

    @ViewBuilder
    private func advancedSection(visibleRows: [SettingsRowID], isCompact: Bool) -> some View {
        SettingsSectionSurface(
            icon: .slidersHorizontal,
            title: "Advanced",
            collapsedHelper: "Typing speed and reset.",
            isCollapsible: true,
            isExpanded: Binding(
                get: { isAdvancedEffectiveExpanded },
                set: { isAdvancedUserExpanded = $0 }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider().overlay(DS.Color.borderSubtle)
                    }

                    switch row {
                    case .typingSpeed:
                        SettingsRowContainer(
                            title: "Typing speed",
                            helper: "Used to estimate time saved on your Dashboard.",
                            isWideControl: true,
                            isCompact: isCompact
                        ) {
                            VStack(alignment: isCompact ? .leading : .trailing, spacing: 4) {
                                HStack(spacing: 6) {
                                    TextField("", text: $typingWPMText)
                                        .textFieldStyle(.plain)
                                        .settingsControlSurface()
                                        .frame(width: DS.Layout.settingsNumericFieldWidth)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: typingWPMText) { _, newVal in
                                            validateAndSaveWPM(newVal)
                                        }

                                    Text("words/min")
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.textSecondary)
                                }

                                if let wpmError {
                                    Text(wpmError)
                                        .font(DS.Font.captionSmall)
                                        .foregroundStyle(DS.Color.textSecondary)
                                }
                            }
                        }
                    case .resetSettings:
                        SettingsRowContainer(
                            title: "Reset settings",
                            helper: "Restore default preferences. Keep history and dictionary.",
                            isWideControl: true,
                            isCompact: isCompact
                        ) {
                            MurmurButton("Reset settings…", style: .secondary) {
                                isConfirmingReset = true
                            }
                            .help("Restore Murmur's default preferences")
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptySearchState: some View {
        VStack(spacing: DS.Space.snug) {
            LucideIcon(.search, size: 28)
                .foregroundStyle(DS.Color.textTertiary)
                .padding(.bottom, 4)

            Text("No settings found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)

            Text("Try another keyword.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }

    // MARK: - Validation & Persistence Helpers

    private func validateAndSaveWPM(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            wpmError = "Value cannot be empty."
            return
        }
        guard let num = Int(trimmed) else {
            wpmError = "Must be a valid integer."
            return
        }
        guard num > 0 else {
            wpmError = "Must be greater than 0."
            return
        }
        guard num <= 500 else {
            wpmError = "Must be 500 or less."
            return
        }
        wpmError = nil
        settings.typingWPM = num
    }

    // MARK: - Microphone Test Audio Management

    private func startMicTest() {
        micTest.startMicTest(isDictationActive: controller.state.isActive)
    }

    private func stopMicTest() {
        micTest.stopMicTest()
    }
}

// MARK: - Settings Header Component

struct SettingsHeader: View {
    @Binding var searchQuery: String
    var isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.card) {
            Group {
                if isCompact {
                    VStack(alignment: .leading, spacing: DS.Space.base) {
                        titleBlock
                        searchField
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .center, spacing: DS.Space.wide) {
                        titleBlock
                        Spacer(minLength: DS.Space.wide)
                        searchField
                            .frame(width: DS.Layout.settingsSearchWidth)
                    }
                }
            }

            Divider()
                .overlay(DS.Color.borderSubtle)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text("Settings")
                .font(DS.Font.pageTitle)
                .foregroundStyle(DS.Color.textPrimary)

            Text("Customize Murmur to work the way you do.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.snug) {
            LucideIcon(.search, size: 14)
                .foregroundStyle(DS.Color.textTertiary)

            TextField("Search settings…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    LucideIcon(.xmark, size: 12)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Space.base)
        .frame(height: DS.Layout.settingsSearchHeight)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }
}

// MARK: - Settings Section Surface Component

struct SettingsSectionSurface<Content: View>: View {
    let icon: LucideIcon.Name
    let title: String
    var collapsedHelper: String? = nil
    var isCollapsible: Bool = false
    var isExpanded: Binding<Bool>? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            // Section heading sits outside the grouped rows, matching native settings hierarchy.
            if isCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded?.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: DS.Space.snug) {
                        LucideIcon(icon, size: DS.Layout.settingsSectionIconSize)
                            .foregroundStyle(DS.Color.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(DS.Font.sectionTitle)
                                .foregroundStyle(DS.Color.textPrimary)

                            if isExpanded?.wrappedValue == false, let collapsedHelper {
                                Text(collapsedHelper)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }

                        Spacer()

                        LucideIcon(isExpanded?.wrappedValue == true ? .chevronDown : .chevronRight, size: 14)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(isExpanded?.wrappedValue == true ? "expanded" : "collapsed")")
                .accessibilityHint(isExpanded?.wrappedValue == true ? "Collapse section" : "Expand section")
            } else {
                HStack(spacing: DS.Space.snug) {
                    LucideIcon(icon, size: DS.Layout.settingsSectionIconSize)
                        .foregroundStyle(DS.Color.textSecondary)

                    Text(title)
                        .font(DS.Font.sectionTitle)
                        .foregroundStyle(DS.Color.textPrimary)

                    Spacer()
                }
            }

            // Body Content
            if !isCollapsible || isExpanded?.wrappedValue == true {
                content
                    .padding(.horizontal, DS.Space.card)
                    .padding(.vertical, DS.Space.snug)
                    .background(DS.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                            .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                    )
                    .shadow(
                        color: DS.Shadow.subtle.color,
                        radius: DS.Shadow.subtle.radius,
                        x: DS.Shadow.subtle.x,
                        y: DS.Shadow.subtle.y
                    )
            }
        }
    }
}

// MARK: - Settings Row Container Component

struct SettingsRowContainer<Control: View>: View {
    let title: String
    var helper: String? = nil
    var note: String? = nil
    var isWideControl: Bool = false
    var isCompact: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        Group {
            if isCompact && isWideControl {
                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    labelColumn
                    control
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, DS.Space.base)
            } else {
                HStack(alignment: .center, spacing: DS.Space.wide) {
                    labelColumn
                        .frame(maxWidth: .infinity, alignment: .leading)

                    control
                        .frame(
                            width: isWideControl ? DS.Layout.settingsControlColumnWidth : nil,
                            alignment: .trailing
                        )
                }
                .frame(minHeight: DS.Layout.settingsRowMinHeight)
                .padding(.vertical, DS.Space.base)
            }
        }
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let helper, !helper.isEmpty {
                Text(helper)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note, !note.isEmpty {
                HStack(spacing: 4) {
                    LucideIcon(.info, size: 12)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(note)
                        .font(DS.Font.captionSmall)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }
}

private extension View {
    func settingsControlSurface() -> some View {
        self
            .padding(.horizontal, DS.Space.snug)
            .padding(.vertical, DS.Space.tight)
            .background(DS.Color.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
            )
    }
}

// MARK: - Microphone Test Inline View

struct MicrophoneTestInlineView: View {
    let level: Float
    let errorMessage: String?
    let onStop: () -> Void

    private var meterColor: Color {
        if level > 0.85 { return DS.Color.recordRed }
        if level > 0.65 { return DS.Color.warningAmber }
        return DS.Color.successGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            // Level Meter Bar
            HStack(spacing: DS.Space.base) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Color.cardElevated)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(meterColor)
                            .frame(width: max(4, w * CGFloat(level)), height: 6)
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f%%", level * 100))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: DS.Layout.settingsMeterValueWidth, alignment: .trailing)
            }

            // Subtitle & Actions
            HStack {
                Text("Microphone test only. Nothing is typed into other apps.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DS.Color.textTertiary)

                Spacer()

                Button("Stop", action: onStop)
                    .font(DS.Font.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.recordRed)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Font.captionSmall)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .padding(DS.Space.base)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
    }
}
