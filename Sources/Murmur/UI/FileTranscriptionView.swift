import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Model option entry for the file transcription selector.
struct FileTranscriptionModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let label: String
    let section: String

    var menuTitle: String {
        "\(name) — \(label)"
    }
}

/// The dedicated File Transcription view for Murmur.
///
/// Features independent model selection, snapshot parameter isolation,
/// drag-and-drop ingestion, progress feedback, and transcript export.
public struct FileTranscriptionView: View {
    @State private var service = FileTranscriptionService.shared
    @State private var modelManager = VoiceModelManager.shared
    @State private var writingModelManager = WritingModelManager.shared
    @State private var settings = Settings.shared

    @State private var selectedFileURL: URL?
    @State private var isTargetedForDrop = false
    @State private var copyFeedback = false

    // Catalog of verified local engines supported for file transcription
    private let availableModels: [FileTranscriptionModelOption] = [
        // WHISPER
        FileTranscriptionModelOption(
            id: "whisper-large-v3",
            name: "Whisper Large v3",
            label: "Maximum Accuracy",
            section: "WHISPER"
        ),
        FileTranscriptionModelOption(
            id: "whisper-large-v3-turbo",
            name: "Whisper Large v3 Turbo",
            label: "Fast + Accurate",
            section: "WHISPER"
        ),
        FileTranscriptionModelOption(
            id: "whisper-medium",
            name: "Whisper Medium",
            label: "Balanced",
            section: "WHISPER"
        ),
        FileTranscriptionModelOption(
            id: "whisper-small",
            name: "Whisper Small",
            label: "Lightweight",
            section: "WHISPER"
        ),

        // OTHER LOCAL MODELS
        FileTranscriptionModelOption(
            id: "parakeet-v3",
            name: "Parakeet TDT v3",
            label: "Very Fast",
            section: "OTHER LOCAL MODELS"
        ),
        FileTranscriptionModelOption(
            id: "parakeet-v2",
            name: "Parakeet TDT v2",
            label: "English",
            section: "OTHER LOCAL MODELS"
        ),
        FileTranscriptionModelOption(
            id: "apple-speech",
            name: "Apple Speech",
            label: "Native",
            section: "OTHER LOCAL MODELS"
        )
    ]

    private let supportedLanguages: [(id: String, name: String)] = [
        ("auto", "Auto Detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("hi", "Hindi"),
        ("ur", "Urdu"),
        ("ja", "Japanese"),
        ("zh", "Chinese")
    ]

    public init() {}

    private var currentModelOption: FileTranscriptionModelOption {
        availableModels.first(where: { $0.id == settings.fileTranscriptionModelID })
            ?? availableModels[0]
    }

    private var isCurrentModelInstalled: Bool {
        modelManager.isModelInstalled(id: settings.fileTranscriptionModelID)
    }

    private var romanScriptAvailable: Bool {
        settings.fileTranscriptionModelID.hasPrefix("whisper") &&
            ["auto", "hi", "ur"].contains(settings.fileTranscriptionLanguage)
    }

    private var romanScriptEnabled: Bool { romanScriptAvailable && settings.fileTranscriptionRomanScript }

    private var needsWritingModel: Bool { settings.fileTranscriptionCleanup != .off || romanScriptEnabled }

    private var isWritingModelReady: Bool {
        writingModelManager.runtimeAvailable && writingModelManager.fileTranscriptionModelURL != nil
    }

    private var canStartTranscription: Bool {
        isCurrentModelInstalled && (!needsWritingModel || isWritingModelReady)
    }

    private var currentModelDescriptor: VoiceModelDescriptor? {
        modelManager.models.first(where: { $0.id == settings.fileTranscriptionModelID })
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                // Header
                PageHeader(
                    title: "File Transcription",
                    subtitle: "Transcribe audio and video recordings on-device with maximum accuracy."
                )

                // Dedicated Top Control Bar (Model, Language, Cleanup, Roman script)
                topControlBar

                // Uninstalled Model Warning Banner (uses VoiceModelManager)
                if !isCurrentModelInstalled {
                    uninstalledModelBanner
                }
                if needsWritingModel && !isWritingModelReady {
                    writingModelBanner
                }

                // Main Content: Drop Zone or Active Results
                switch service.state {
                case .idle:
                    if let fileURL = selectedFileURL {
                        selectedFileCard(fileURL)
                    } else {
                        dropZoneView
                    }

                case .loadingAudio, .loadingModel, .transcribing, .formatting:
                    processingProgressView

                case .completed(let result):
                    transcriptionResultView(result)

                case .error(let message):
                    errorCard(message)
                }

                // Recent Files Section
                if !service.recentResults.isEmpty && !service.state.isProcessing {
                    recentFilesSection
                }
            }
            .padding(DS.Space.panel)
        }
        .background(DS.Color.canvas)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        MurmurCard(padding: DS.Space.base) {
            HStack(spacing: DS.Space.base) {
                // Model Selector
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Model")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)

                    Menu {
                        Section("WHISPER") {
                            ForEach(availableModels.filter { $0.section == "WHISPER" }) { option in
                                Button {
                                    settings.fileTranscriptionModelID = option.id
                                } label: {
                                    HStack {
                                        Text(option.menuTitle)
                                        if settings.fileTranscriptionModelID == option.id {
                                            LucideIcon(.check, size: 12)
                                        }
                                    }
                                }
                            }
                        }

                        Section("OTHER LOCAL MODELS") {
                            ForEach(availableModels.filter { $0.section == "OTHER LOCAL MODELS" }) { option in
                                Button {
                                    settings.fileTranscriptionModelID = option.id
                                } label: {
                                    HStack {
                                        Text(option.menuTitle)
                                        if settings.fileTranscriptionModelID == option.id {
                                            LucideIcon(.check, size: 12)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            Text(currentModelOption.menuTitle)
                                .font(DS.Font.bodyEmphasis)
                                .foregroundStyle(DS.Color.textPrimary)
                            LucideIcon(.chevronDown, size: 10)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Space.snug)
                        .padding(.vertical, DS.Space.tight)
                        .background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 28)
                    .overlay(DS.Color.borderSubtle)

                // Language Selector
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Language")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)

                    Menu {
                        ForEach(supportedLanguages, id: \.id) { lang in
                            Button {
                                settings.fileTranscriptionLanguage = lang.id
                            } label: {
                                HStack {
                                    Text(lang.name)
                                    if settings.fileTranscriptionLanguage == lang.id {
                                        LucideIcon(.check, size: 12)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            let currentName = supportedLanguages.first(where: { $0.id == settings.fileTranscriptionLanguage })?.name ?? "Auto Detect"
                            Text(currentName)
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                            LucideIcon(.chevronDown, size: 10)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Space.snug)
                        .padding(.vertical, DS.Space.tight)
                        .background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 28)
                    .overlay(DS.Color.borderSubtle)

                // Cleanup Selector
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Cleanup")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)

                    Menu {
                        ForEach([CleanupMode.smart, .off], id: \.self) { mode in
                            Button {
                                settings.fileTranscriptionCleanup = mode
                            } label: {
                                HStack {
                                    Text(mode == .off ? "Off" : "On")
                                    if (settings.fileTranscriptionCleanup == .off) == (mode == .off) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            Text(settings.fileTranscriptionCleanup == .off ? "Off" : "On")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: DS.Material.iconSizeSmall - 3, weight: .bold))
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Space.snug)
                        .padding(.vertical, DS.Space.tight)
                        .background(DS.Color.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if romanScriptAvailable {
                    Divider()
                        .frame(height: 28)
                        .overlay(DS.Color.borderSubtle)

                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text("Roman script")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        Button {
                            settings.fileTranscriptionRomanScript.toggle()
                        } label: {
                            Text(settings.fileTranscriptionRomanScript ? "On" : "Off")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                                .padding(.horizontal, DS.Space.snug)
                                .padding(.vertical, DS.Space.tight)
                                .background(DS.Color.cardElevated)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline))
                        }
                        .buttonStyle(.plain)
                        .help("Write detected Hindi or Urdu speech in Roman letters. Original text stays available.")
                    }
                }

                Spacer()

                HStack(spacing: DS.Space.tight) {
                    LucideIcon(isCurrentModelInstalled ? .shield : .download, size: DS.Material.iconSizeSmall)
                    Text(isCurrentModelInstalled ? "On-device" : "Model required")
                        .font(DS.Font.caption)
                }
                .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    // MARK: - Model Readiness Banners

    private var writingModelBanner: some View {
        MurmurCard(padding: DS.Space.card) {
            HStack(spacing: DS.Space.wide) {
                LucideIcon(.sparkles, size: 20)
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(romanScriptEnabled ? "Roman script needs a Writing & Cleanup model" : "Cleanup On needs a Writing & Cleanup model")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(writingModelManager.runtimeAvailable
                         ? "Download a local writing model, or turn off Cleanup and Roman script for the raw transcript."
                         : "This build cannot run the local writing model. Turn off Cleanup and Roman script for the raw transcript.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                if writingModelManager.runtimeAvailable {
                    Button("Choose Model") {
                        NotificationCenter.default.post(name: .murmurNavigate, object: SidebarDestination.models)
                        Task { @MainActor in
                            await Task.yield()
                            NotificationCenter.default.post(name: .murmurNavigate, object: "writing-models")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    private var uninstalledModelBanner: some View {
        MurmurCard(padding: DS.Space.card) {
            HStack(spacing: DS.Space.wide) {
                ZStack {
                    Circle()
                        .fill(DS.Color.accentSoft)
                        .frame(width: DS.Material.iconSizeHero, height: DS.Material.iconSizeHero)
                    LucideIcon(.download, size: 20)
                        .foregroundStyle(DS.Color.accent)
                }

                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("\(currentModelOption.name) is not installed.")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)

                    Text("Download the high-accuracy neural engine weights to transcribe files locally.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)

                    if let desc = currentModelDescriptor {
                        switch desc.status {
                        case .downloading(let fraction, let phase):
                            VStack(alignment: .leading, spacing: DS.Space.tight) {
                                ProgressView(value: fraction)
                                    .progressViewStyle(.linear)
                                    .tint(DS.Color.accent)

                                Text(phase)
                                    .font(DS.Font.captionSmall)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                            .padding(.top, DS.Space.tight)

                        case .error(let err):
                            Text("Download error: \(err)")
                                .font(DS.Font.captionSmall)
                                .foregroundStyle(DS.Color.recordRed)
                        default:
                            EmptyView()
                        }
                    }
                }

                Spacer()

                if let desc = currentModelDescriptor, case .downloading = desc.status {
                    Button("Cancel") {
                        modelManager.cancelDownload(for: settings.fileTranscriptionModelID)
                    }
                    .font(DS.Font.body)
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.base)
                    .padding(.vertical, DS.Space.snug)
                    .background(DS.Color.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                } else {
                    Button {
                        modelManager.startDownload(for: settings.fileTranscriptionModelID)
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            LucideIcon(.download, size: 14)
                            Text("Download Model")
                        }
                        .font(DS.Font.bodyEmphasis)
                        .foregroundStyle(DS.Color.textOnAccent)
                        .padding(.horizontal, DS.Space.roomy)
                        .padding(.vertical, DS.Space.snug)
                        .background(DS.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        Button {
            openFilePicker()
        } label: {
            VStack(spacing: DS.Space.base) {
                ZStack {
                    Circle()
                        .fill(isTargetedForDrop ? DS.Color.accentSoft : DS.Color.cardElevated)
                        .frame(width: 56, height: 56)

                    LucideIcon(.fileAudio, size: 24)
                        .foregroundStyle(isTargetedForDrop ? DS.Color.accent : DS.Color.textSecondary)
                }

                VStack(spacing: DS.Space.tight) {
                    Text("Drop audio or video files here")
                        .font(DS.Font.cardTitleLarge)
                        .foregroundStyle(DS.Color.textPrimary)

                    Text("Supports MP3, M4A, WAV, MP4, MOV, FLAC, and AAC")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Text("or click to browse")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.accent)
                    .padding(.top, DS.Space.tight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Material.dropZoneHeight)
            .background(isTargetedForDrop ? DS.Color.cardSelected : DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
                    .strokeBorder(
                        isTargetedForDrop ? DS.Color.accent : DS.Color.borderSubtle,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in
                        self.selectedFileURL = url
                    }
                }
            }
            return true
        }
    }

    // MARK: - Selected File Card

    private func selectedFileCard(_ url: URL) -> some View {
        MurmurCard(padding: DS.Space.card) {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                HStack(spacing: DS.Space.wide) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.control)
                            .fill(DS.Color.accentSoft)
                            .frame(width: 44, height: 44)
                        LucideIcon(.fileAudio, size: 20)
                            .foregroundStyle(DS.Color.accent)
                    }

                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Text(url.lastPathComponent)
                            .font(DS.Font.cardTitleLarge)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineLimit(1)

                        Text(url.path)
                            .font(DS.Font.captionSmall)
                            .foregroundStyle(DS.Color.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        selectedFileURL = nil
                    } label: {
                        LucideIcon(.xmark, size: 14)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("Choose different file") {
                        openFilePicker()
                    }
                    .font(DS.Font.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textSecondary)

                    Spacer()

                    Button {
                        startTranscription()
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            LucideIcon(.play, size: 13)
                            Text("Transcribe with \(currentModelOption.name)")
                        }
                        .font(DS.Font.bodyEmphasis)
                        .foregroundStyle(DS.Color.textOnAccent)
                        .padding(.horizontal, DS.Space.roomy)
                        .padding(.vertical, DS.Space.base)
                        .background(canStartTranscription ? DS.Color.accent : DS.Color.border)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartTranscription)
                }
            }
        }
    }

    // MARK: - Processing Progress View

    private var processingProgressView: some View {
        MurmurCard(padding: DS.Space.card) {
            VStack(spacing: DS.Space.wide) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(DS.Color.accent)

                VStack(spacing: DS.Space.tight) {
                    Text(progressStageText)
                        .font(DS.Font.cardTitleLarge)
                        .foregroundStyle(DS.Color.textPrimary)

                    if let job = service.activeJob {
                        Text("\(job.fileName) · \(job.modelDisplayName) · Cleanup \(job.cleanupMode == .off ? "Off" : "On")")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                Button("Cancel Transcription") {
                    service.cancel()
                }
                .font(DS.Font.body)
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.base)
                .padding(.vertical, DS.Space.tight)
                .background(DS.Color.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.panel)
        }
    }

    private var progressStageText: String {
        switch service.state {
        case .loadingAudio:
            return "Analyzing and decoding audio track…"
        case .loadingModel(let name):
            return "Loading \(name) into Neural Engine…"
        case .transcribing:
            return "Transcribing speech on-device…"
        case .formatting:
            return "Preparing the transcript with the Writing & Cleanup model…"
        default:
            return "Processing…"
        }
    }

    // MARK: - Transcription Result View

    private func transcriptionResultView(_ result: FileTranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            MurmurCard(padding: DS.Space.card) {
                VStack(alignment: .leading, spacing: DS.Space.roomy) {
                    // File details & actions
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: DS.Space.tight) {
                            Text(result.fileName)
                                .font(DS.Font.cardTitleLarge)
                                .foregroundStyle(DS.Color.textPrimary)

                            Text("\(result.modelDisplayName) • \(result.audioDurationString) audio • \(result.processDurationString) processing • \(result.realtimeFactorString)")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                            if !result.detectedLanguages.isEmpty {
                                Text("\(result.language == "auto" ? "Detected" : "Language"): \(result.detectedLanguages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", "))")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }

                        Spacer()

                        // Action buttons
                        HStack(spacing: DS.Space.snug) {
                            Button {
                                copyTranscript(result.text)
                            } label: {
                                HStack(spacing: DS.Space.tight) {
                                    LucideIcon(copyFeedback ? .check : .copy, size: 13)
                                    Text(copyFeedback ? "Copied" : "Copy")
                                }
                                .font(DS.Font.bodyEmphasis)
                                .foregroundStyle(copyFeedback ? DS.Color.textPrimary : DS.Color.textOnAccent)
                                .padding(.horizontal, DS.Space.base)
                                .padding(.vertical, DS.Space.snug)
                                .background(copyFeedback ? DS.Color.cardElevated : DS.Color.accent)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button("Export as Plain Text (.txt)") {
                                    exportTranscript(result.text, defaultName: "\(result.fileName).txt")
                                }
                                if result.romanScriptApplied {
                                    Button("Export original transcript (.txt)") {
                                        exportTranscript(result.rawText, defaultName: "\(result.fileName).original.txt")
                                    }
                                }
                                Button("Export as JSON (.json)") {
                                    if let data = try? JSONEncoder().encode(result.text), let str = String(data: data, encoding: .utf8) {
                                        exportTranscript(str, defaultName: "\(result.fileName).json")
                                    }
                                }
                            } label: {
                                HStack(spacing: DS.Space.tight) {
                                    LucideIcon(.download, size: 13)
                                    Text("Export")
                                }
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                                .padding(.horizontal, DS.Space.base)
                                .padding(.vertical, DS.Space.snug)
                                .background(DS.Color.cardElevated)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.control)
                                        .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                service.clear()
                                selectedFileURL = nil
                            } label: {
                                LucideIcon(.xmark, size: 13)
                                    .foregroundStyle(DS.Color.textSecondary)
                                    .padding(DS.Space.snug)
                                    .background(DS.Color.cardElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                            }
                            .buttonStyle(.plain)
                            .help("Transcribe another file")
                        }
                    }

                    Divider()
                        .overlay(DS.Color.borderSubtle)

                    if let warning = result.romanWarning {
                        Text(warning)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    if let warning = result.cleanupWarning {
                        Text("Cleanup could not finish: \(warning) \(result.romanScriptApplied ? "Roman script was made from the original transcript." : "Raw transcription is shown.")")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    } else if result.romanScriptApplied {
                        Text("Roman script")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    } else if let engine = result.cleanupEngine {
                        Text("Cleaned with \(engine)")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    } else {
                        Text("Raw transcription")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }

                    // Transcript Text Box
                    ScrollView {
                        Text(result.text)
                            .font(DS.Font.bodyLarge)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineSpacing(DS.Space.tight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: DS.Material.minTextEditorHeight, maxHeight: 400)

                    if result.romanScriptApplied {
                        DisclosureGroup("Original transcript") {
                            VStack(alignment: .leading, spacing: DS.Space.snug) {
                                Button("Copy original") { copyTranscript(result.rawText) }
                                    .font(DS.Font.caption)
                                    .buttonStyle(.plain)
                                Text(result.rawText)
                                    .font(DS.Font.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        MurmurCard(padding: DS.Space.card) {
            VStack(alignment: .leading, spacing: DS.Space.base) {
                HStack(spacing: DS.Space.snug) {
                    LucideIcon(.alertCircle, size: 16)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Transcription Failed")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                }

                Text(message)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)

                HStack {
                    Spacer()

                    Button("Dismiss") {
                        service.clear()
                    }
                    .font(DS.Font.body)
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.base)
                    .padding(.vertical, DS.Space.tight)
                    .background(DS.Color.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Recent Files Section

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text("Recent File Transcripts")
                .font(DS.Font.sectionTitle)
                .foregroundStyle(DS.Color.textPrimary)

            VStack(spacing: DS.Space.base) {
                ForEach(service.recentResults) { item in
                    MurmurCard(padding: DS.Space.base) {
                        HStack(spacing: DS.Space.wide) {
                            VStack(alignment: .leading, spacing: DS.Space.tight) {
                                Text(item.fileName)
                                    .font(DS.Font.bodyEmphasis)
                                    .foregroundStyle(DS.Color.textPrimary)

                                Text("\(item.modelDisplayName) · \(item.audioDurationString) · \(item.realtimeFactorString)")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }

                            Spacer()

                            Button("Copy") {
                                copyTranscript(item.text)
                            }
                            .font(DS.Font.caption)
                            .buttonStyle(.plain)
                            .padding(.horizontal, DS.Space.snug)
                            .padding(.vertical, DS.Space.tight)
                            .background(DS.Color.cardElevated)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                            if item.romanScriptApplied {
                                Button("Copy original") { copyTranscript(item.rawText) }
                                    .font(DS.Font.caption)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.movie,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.mp3,
            UTType.wav
        ]

        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
        }
    }

    private func startTranscription() {
        guard let url = selectedFileURL, canStartTranscription else { return }
        service.startTranscription(
            fileURL: url,
            modelID: settings.fileTranscriptionModelID,
            language: settings.fileTranscriptionLanguage,
            cleanupMode: settings.fileTranscriptionCleanup,
            romanScript: romanScriptEnabled
        )
    }

    private func copyTranscript(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(DS.Motion.panel) {
            copyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(DS.Motion.panel) {
                copyFeedback = false
            }
        }
    }

    private func exportTranscript(_ text: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName

        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
