import SwiftUI

struct WritingModelsView: View {
    @Binding var writing: Bool
    @State private var manager = WritingModelManager.shared
    @State private var settings = Settings.shared
    @State private var filter: ModelCatalogFilter = .all
    @State private var removal: WritingModelDescriptor?
    @State private var expandedModelID: String?
    @State private var hoveredMenuID: String?

    init(writing: Binding<Bool>) {
        _writing = writing
    }

    private var selectedModel: WritingModelDescriptor? {
        guard settings.cleanupEnabled, settings.smartCleanup, manager.runtimeAvailable,
              settings.writingEngine == .qwen,
              manager.selectedModelURL != nil,
              let id = manager.selectedModelID,
              manager.state(for: id).isInstalled else { return nil }
        return manager.catalog.first(where: { $0.id == id })
    }

    private var modelSummary: ModelCatalogSummary<WritingModelDescriptor> {
        ModelCatalogSummary(models: manager.catalog, activeModelID: selectedModel?.id) {
            manager.state(for: $0.id).isInstalled
        }
    }

    private var visibleModels: [WritingModelDescriptor] {
        let additionalModels = modelSummary.additionalModels
        return switch filter {
        case .all: additionalModels
        case .installed: additionalModels.filter { manager.state(for: $0.id).isInstalled }
        case .available: additionalModels.filter { !manager.state(for: $0.id).isInstalled }
        }
    }

    private var currentTitle: String {
        if !settings.cleanupEnabled { return "Cleanup off" }
        if !settings.smartCleanup || settings.writingEngine == .rules { return "Basic cleanup" }
        if settings.writingEngine == .qwen && selectedModel == nil { return "Basic cleanup" }
        if settings.writingEngine == .apple && !FoundationModelFormatter.isAvailable { return "Basic cleanup" }
        return selectedModel?.name ?? settings.writingEngine.displayName
    }

    private var currentSummary: String {
        if !settings.cleanupEnabled { return "Dictation continues without a cleanup pass" }
        if !settings.smartCleanup || settings.writingEngine == .rules {
            return "Rules-based formatting · Built into Murmur"
        }
        if let selectedModel { return "On-device writing · \(selectedModel.downloadSize)" }
        switch settings.writingEngine {
        case .apple: return FoundationModelFormatter.unavailableReason ?? "System managed · On your Mac"
        case .qwen:
            return manager.fileTranscriptionModelURL == nil
                ? "Choose and download a Qwen model below. Basic cleanup remains available."
                : "Choose Use on an installed Qwen model to make it active for dictation."
        case .rules: return "Rules-based formatting · Built into Murmur"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(title: "Writing Models", subtitle: "Choose a local model for cleanup, writing styles and meeting notes.") {
                    ModelPurposePicker(writing: $writing)
                }

                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    Text("Now Using")
                        .font(DS.Font.sectionTitle)
                        .foregroundStyle(DS.Color.textPrimary)

                    MurmurCard(padding: DS.Space.roomy) {
                        HStack(spacing: DS.Space.roomy) {
                            LucideIcon(currentTitle == "Basic cleanup" || currentTitle == "Cleanup off" ? .brushCleaning : .fileText,
                                       size: DS.Material.iconSizeLarge)
                                .foregroundStyle(DS.Color.textPrimary)
                                .frame(width: DS.VoiceModels.activeIconFrame, height: DS.VoiceModels.activeIconFrame)
                                .background(DS.Color.cardSelected)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DS.Space.tight) {
                                Text(currentTitle)
                                    .font(DS.Font.cardTitleLarge)
                                    .foregroundStyle(DS.Color.textPrimary)
                                Text(currentSummary)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: DS.Space.snug)
                            if settings.cleanupEnabled {
                                ActiveStatusPill()
                            } else {
                                Text("Off")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    ModelCatalogHeading(
                        filter: $filter,
                        allCount: modelSummary.all,
                        installedCount: modelSummary.installed,
                        availableCount: modelSummary.available,
                        filterLabel: "Filter writing models"
                    )

                    MurmurCard(padding: DS.Space.base) {
                        if visibleModels.isEmpty {
                            Text(filter == .installed
                                 ? "No additional writing models are installed."
                                 : "No writing models are available in this filter.")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textSecondary)
                        } else {
                            VStack(spacing: DS.Space.none) {
                                ForEach(Array(visibleModels.enumerated()), id: \.element.id) { index, model in
                                    modelRow(model)
                                    if index < visibleModels.count - 1 {
                                        Divider().overlay(DS.Color.borderSubtle)
                                    }
                                }
                            }
                        }
                    }
                }

                if !manager.runtimeAvailable {
                    Label("This build is missing its writing engine. A complete Murmur release includes it automatically.", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                if let error = manager.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                HStack {
                    Link("Qwen license", destination: URL(string: "https://huggingface.co/Qwen/Qwen3.5-4B/blob/main/LICENSE")!)
                    Link("Model source", destination: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF")!)
                }
                .font(DS.Font.caption)
            }
            .padding(DS.Space.panel)
        }
        .background(DS.Color.canvas)
        .confirmationDialog("Delete writing model?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), titleVisibility: .visible) {
            if let removal {
                Button("Delete \(removal.name)", role: .destructive) {
                    manager.remove(id: removal.id)
                    self.removal = nil
                }
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: {
            Text("The model can be downloaded again. Your transcripts, dictionary and personal writing preferences are kept.")
        }
    }

    @ViewBuilder
    private func modelRow(_ model: WritingModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(alignment: .center, spacing: DS.Space.roomy) {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(model.name)
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    HStack(spacing: DS.Space.snug) {
                        LucideIcon(.fileText, size: DS.Material.iconSizeSmall)
                            .foregroundStyle(DS.Color.metricWords)
                        Text(model.shortSummary)
                        Divider()
                            .frame(height: DS.VoiceModels.profileSeparatorHeight)
                            .overlay(DS.Color.borderSubtle)
                        Text(model.downloadSize)
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .help(model.summary)
                    if case .error(let message) = manager.state(for: model.id) {
                        Text(message)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: DS.Space.base)
                actions(model)
            }
            .frame(minHeight: DS.Layout.voiceModelsRowMinHeight)

            switch manager.state(for: model.id) {
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading · \(Int(fraction * 100))%")
                        .font(DS.Font.caption)
                }
                .tint(DS.Color.textPrimary)
                .accessibilityLabel("Downloading \(model.name)")
                .accessibilityValue("\(Int(fraction * 100)) percent")
            case .paused:
                Text("Paused. Resume to continue the download.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            default: EmptyView()
            }
            if expandedModelID == model.id {
                Divider().overlay(DS.Color.borderSubtle)
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(model.summary)
                    Text(model.fileName)
                    Text("Verified SHA-256 · pinned model revision")
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .textSelection(.enabled)
                .transition(.opacity)
            }
        }
        .padding(.vertical, DS.Space.tight)
    }

    private func actions(_ model: WritingModelDescriptor) -> some View {
        HStack(spacing: DS.VoiceModels.actionGap) {
            primaryAction(model)
            overflowMenu(model)
        }
        .frame(minWidth: DS.VoiceModels.actionAreaWidth, alignment: .trailing)
        .padding(.trailing, DS.VoiceModels.actionTrailingPadding)
    }

    @ViewBuilder
    private func primaryAction(_ model: WritingModelDescriptor) -> some View {
        switch manager.state(for: model.id) {
        case .notInstalled: ModelRowActionButton("Download") { manager.download(id: model.id) }
        case .downloading: ModelRowActionButton("Pause") { manager.cancelDownload(id: model.id) }
        case .verifying:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking \(model.name)")
        case .installed:
            ModelRowActionButton("Use") {
                manager.select(id: model.id)
                settings.writingEngine = .qwen
                settings.cleanupEnabled = true
                settings.smartCleanup = true
            }
        case .paused: ModelRowActionButton("Resume") { manager.download(id: model.id) }
        case .error: ModelRowActionButton("Retry") { manager.download(id: model.id) }
        }
    }

    private func overflowMenu(_ model: WritingModelDescriptor) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous)
                .fill(hoveredMenuID == model.id ? DS.Color.modelActionSurfaceHover : DS.Color.modelActionSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous)
                        .strokeBorder(
                            hoveredMenuID == model.id ? DS.Color.modelActionBorderHover : DS.Color.modelActionBorder,
                            lineWidth: DS.Border.standard
                        )
                )
            LucideIcon(.ellipsis, size: DS.VoiceModels.moreIconSize)
                .foregroundStyle(hoveredMenuID == model.id ? DS.Color.modelMenuForegroundHover : DS.Color.modelMenuForeground)
            Menu {
                Button(expandedModelID == model.id ? "Hide details" : "Model details") {
                    withAnimation(DS.Motion.panel) {
                        expandedModelID = expandedModelID == model.id ? nil : model.id
                    }
                }
                Button("Reveal in Finder") { manager.revealInFinder(id: model.id) }
                    .disabled(!manager.state(for: model.id).isInstalled)
                Divider()
                Button("Delete model", role: .destructive) { removal = model }
                    .disabled(!manager.state(for: model.id).isInstalled)
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
        }
        .frame(width: DS.VoiceModels.menuButtonSize, height: DS.VoiceModels.menuButtonSize)
        .clipShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
        .animation(DS.Motion.hover, value: hoveredMenuID)
        .onHover { hoveredMenuID = $0 ? model.id : nil }
        .help("More options")
        .accessibilityLabel("Actions for \(model.name)")
    }
}
