import SwiftUI
import AppKit

/// Voice Models manager view for Murmur.
/// Keeps the default catalog concise while preserving technical information on demand.
public struct VoiceModelsView: View {
    @Binding private var writing: Bool
    @State private var modelManager = VoiceModelManager.shared
    @State private var filter: ModelCatalogFilter = .all
    @State private var errorMessage: String? = nil
    @State private var deletion: VoiceModelDescriptor?

    public init(writing: Binding<Bool>) {
        _writing = writing
    }

    private var activeModel: VoiceModelDescriptor? {
        modelManager.models.first(where: { $0.id == modelManager.activeModelID })
    }

    private var modelSummary: ModelCatalogSummary<VoiceModelDescriptor> {
        ModelCatalogSummary(models: modelManager.models, activeModelID: activeModel?.id) {
            $0.status.isInstalled
        }
    }

    private var visibleModels: [VoiceModelDescriptor] {
        let additionalModels = modelSummary.additionalModels
        switch filter {
        case .all:
            return additionalModels
        case .installed:
            return additionalModels.filter { $0.status.isInstalled }
        case .available:
            return additionalModels.filter { !$0.status.isInstalled }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(
                    title: "Voice Models",
                    subtitle: "Choose the transcription model used for dictation."
                ) {
                    ModelPurposePicker(writing: $writing)
                }

                if let activeModel {
                    VStack(alignment: .leading, spacing: DS.Space.snug) {
                        Text("Now Using")
                            .font(DS.Font.sectionTitle)
                            .foregroundStyle(DS.Color.textPrimary)

                        ActiveModelCard(model: activeModel)
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    ModelCatalogHeading(
                        filter: $filter,
                        allCount: modelSummary.all,
                        installedCount: modelSummary.installed,
                        availableCount: modelSummary.available,
                        filterLabel: "Filter speech models"
                    )

                    modelCatalog
                }
            }
            .padding(DS.Space.panel)
        }
        .background(DS.Color.canvas)
        .onAppear {
            modelManager.refreshModelStatuses()
        }
        .alert(
            "Model Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Delete voice model?", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        ), titleVisibility: .visible) {
            if let deletion {
                Button("Delete \(deletion.name)", role: .destructive) {
                    removeModel(deletion)
                    self.deletion = nil
                }
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: {
            Text("The model can be downloaded again.")
        }
    }

    @ViewBuilder
    private var modelCatalog: some View {
        if visibleModels.isEmpty {
            MurmurCard(padding: DS.Space.roomy) {
                Text(emptyCatalogMessage)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        } else {
            MurmurCard(padding: DS.Space.base) {
                VStack(spacing: DS.Space.none) {
                    ForEach(Array(visibleModels.enumerated()), id: \.element.id) { index, model in
                        ModelCatalogRow(
                            model: model,
                            onActivate: { activateModel(model) },
                            onDownload: { modelManager.startDownload(for: model.id) },
                            onCancel: { modelManager.cancelDownload(for: model.id) },
                            onRemove: { deletion = model },
                            onReveal: { modelManager.revealInFinder(modelID: model.id) }
                        )

                        if index < visibleModels.count - 1 {
                            Divider()
                                .overlay(DS.Color.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private var emptyCatalogMessage: String {
        return filter == .installed
            ? "No additional models are installed."
            : "No models are available in this filter."
    }

    private func activateModel(_ model: VoiceModelDescriptor) {
        do {
            try modelManager.activate(modelID: model.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeModel(_ model: VoiceModelDescriptor) {
        Task {
            do {
                try await modelManager.remove(modelID: model.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum ModelCatalogFilter: CaseIterable, Hashable {
    case all
    case installed
    case available

    var title: String {
        switch self {
        case .all: "All"
        case .installed: "Installed"
        case .available: "Available"
        }
    }
}

struct ModelFilterControl: View {
    @Binding var selection: ModelCatalogFilter
    let allCount: Int
    let installedCount: Int
    let availableCount: Int
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: DS.Space.none) {
            ForEach(ModelCatalogFilter.allCases, id: \.self) { filter in
                ModelFilterSegment(
                    title: "\(filter.title) (\(count(for: filter)))",
                    isSelected: selection == filter,
                    action: { selection = filter }
                )
            }
        }
        .padding(DS.Space.hair)
        .background(DS.Color.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func count(for filter: ModelCatalogFilter) -> Int {
        switch filter {
        case .all: allCount
        case .installed: installedCount
        case .available: availableCount
        }
    }
}

private struct ModelFilterSegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? DS.Font.bodyEmphasis : DS.Font.body)
                .foregroundStyle(isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                .padding(.horizontal, DS.Space.base)
                .padding(.vertical, DS.Space.tight)
                .background(segmentBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var segmentBackground: Color {
        if isSelected { return DS.Color.cardSelected }
        return isHovering ? DS.Color.hover : .clear
    }
}

// MARK: - Active Model

private struct ActiveModelCard: View {
    let model: VoiceModelDescriptor

    var body: some View {
        MurmurCard(padding: DS.Space.roomy) {
            HStack(alignment: .top) {
                LucideIcon(.waveform, size: DS.Material.iconSizeLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(
                        width: DS.VoiceModels.activeIconFrame,
                        height: DS.VoiceModels.activeIconFrame
                    )
                    .background(DS.Color.cardSelected)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(model.name)
                        .font(DS.Font.cardTitleLarge)
                        .foregroundStyle(DS.Color.textPrimary)

                    ModelProfileSummary(model: model)
                }

                Spacer()

                ActiveStatusPill()
            }
        }
    }
}

struct ActiveStatusPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            ZStack {
                Circle()
                    .stroke(
                        DS.Color.metricAudio.opacity(DS.VoiceModels.activeStatusBorderOpacity),
                        lineWidth: DS.Border.hairline
                    )
                    .frame(
                        width: DS.VoiceModels.activeDotSize,
                        height: DS.VoiceModels.activeDotSize
                    )
                    .scaleEffect(
                        isPulsing
                            ? DS.VoiceModels.activePulseScale
                            : DS.Material.buttonRestScale
                    )
                    .opacity(
                        isPulsing
                            ? DS.VoiceModels.activePulseLiveOpacity
                            : DS.VoiceModels.activePulseRestOpacity
                    )

                Circle()
                    .fill(
                        DS.Color.metricAudio.opacity(DS.VoiceModels.activeStatusDotOpacity)
                    )
                    .frame(
                        width: DS.VoiceModels.activeDotSize,
                        height: DS.VoiceModels.activeDotSize
                    )
            }

            Text("Active")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.metricAudio)
        }
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, DS.Space.tight)
        .background(
            DS.Color.metricAudio.opacity(DS.VoiceModels.activeStatusSurfaceOpacity)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    DS.Color.metricAudio.opacity(DS.VoiceModels.activeStatusBorderOpacity),
                    lineWidth: DS.Border.hairline
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active model")
        .onAppear(perform: updatePulse)
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        isPulsing = false
        guard !reduceMotion else { return }
        withAnimation(DS.Motion.activePulse) {
            isPulsing = true
        }
    }
}

private struct ModelProfileSummary: View {
    let model: VoiceModelDescriptor

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            capability(
                icon: .waveform,
                label: modeLabel,
                color: DS.Color.metricWords
            )
            capability(
                icon: .globe,
                label: languageLabel,
                color: DS.Color.metricAudio
            )

            Divider()
                .frame(height: DS.VoiceModels.profileSeparatorHeight)
                .overlay(DS.Color.borderSubtle)

            Text(sizeLabel)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .font(DS.Font.caption)
        .lineLimit(1)
        .help("\(modeLabel) · \(model.languages.joined(separator: ", ")) · \(sizeLabel)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(modeLabel), \(languageLabel), \(sizeLabel)"
        )
    }

    private func capability(
        icon: LucideIcon.Name,
        label: String,
        color: Color
    ) -> some View {
        HStack(spacing: DS.Space.tight) {
            LucideIcon(icon, size: DS.Material.iconSizeSmall)
                .foregroundStyle(color)
            Text(label)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private var sizeLabel: String {
        if model.isApple { return "System managed" }
        return model.diskSize
    }

    private var modeLabel: String {
        model.isStreaming ? "Live text" : "Dictation"
    }

    private var languageLabel: String {
        model.languages.allSatisfy { $0.lowercased().hasPrefix("english") } ? "English" : "Multilingual"
    }
}

// MARK: - Model Catalog

private struct ModelCatalogRow: View {
    let model: VoiceModelDescriptor
    let onActivate: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    @State private var isExpanded = false
    @State private var isMenuHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(alignment: .center, spacing: DS.Space.roomy) {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(model.name)
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)

                    ModelProfileSummary(model: model)

                    if case .error(let message) = model.status {
                        HStack(spacing: DS.Space.tight) {
                            LucideIcon(.circleAlert, size: DS.Material.iconSizeSmall)
                            Text(message)
                                .lineLimit(2)
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                Spacer(minLength: DS.Space.base)

                actionControls
            }
            .frame(minHeight: DS.Layout.voiceModelsRowMinHeight)

            if case .downloading(let fraction, let phase) = model.status {
                DownloadProgress(fraction: fraction, phase: phase)
            }

            if isExpanded {
                Divider()
                    .overlay(DS.Color.borderSubtle)

                ModelTechnicalDetails(model: model)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, DS.Space.tight)
    }

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: DS.VoiceModels.actionGap) {
            primaryAction
            overflowMenu
        }
        .frame(minWidth: DS.VoiceModels.actionAreaWidth, alignment: .trailing)
        .padding(.trailing, DS.VoiceModels.actionTrailingPadding)
    }

    @ViewBuilder
    private var overflowMenu: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous)
                .fill(
                    isMenuHovered
                        ? DS.Color.modelActionSurfaceHover
                        : DS.Color.modelActionSurface
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous)
                        .strokeBorder(
                            isMenuHovered
                                ? DS.Color.modelActionBorderHover
                                : DS.Color.modelActionBorder,
                            lineWidth: DS.Border.standard
                        )
                )

            LucideIcon(.ellipsis, size: DS.VoiceModels.moreIconSize)
                .foregroundStyle(
                    isMenuHovered
                        ? DS.Color.modelMenuForegroundHover
                        : DS.Color.modelMenuForeground
                )

            Menu {
                Button(isExpanded ? "Hide details" : "Model details") {
                    withAnimation(DS.Motion.panel) { isExpanded.toggle() }
                }

                Button("Reveal in Finder", action: onReveal)
                    .disabled(!model.status.isInstalled || model.isApple)
                Divider()
                Button("Delete model", role: .destructive, action: onRemove)
                    .disabled(!model.status.isInstalled || model.isApple)
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
        }
        .frame(
            width: DS.VoiceModels.menuButtonSize,
            height: DS.VoiceModels.menuButtonSize
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
        .animation(DS.Motion.hover, value: isMenuHovered)
        .onHover { isMenuHovered = $0 }
        .help("More options")
        .accessibilityLabel("Actions for \(model.name)")
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.status {
        case .notInstalled:
            ModelRowActionButton("Download", action: onDownload)
        case .downloading:
            ModelRowActionButton("Cancel", action: onCancel)
        case .verifying:
            Text("Verifying…")
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(minHeight: DS.VoiceModels.actionHeight)
        case .installed:
            ModelRowActionButton("Activate", action: onActivate)
        case .loading:
            ProgressView()
                .frame(minHeight: DS.VoiceModels.actionHeight)
                .accessibilityLabel("Loading \(model.name)")
        case .active:
            ActiveStatusPill()
        case .error:
            ModelRowActionButton("Retry", action: onDownload)
        }
    }
}

/// Dark secondary catalog action used consistently for activate, download, retry and cancel.
struct ModelRowActionButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.modelActionText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, DS.VoiceModels.actionHorizontalPadding)
                .frame(minWidth: DS.VoiceModels.actionButtonMinWidth, minHeight: DS.VoiceModels.actionHeight)
                .background(
                    isHovering
                        ? DS.Color.modelActionSurfaceHover
                        : DS.Color.modelActionSurface
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous)
                        .strokeBorder(
                            isHovering
                                ? DS.Color.modelActionBorderHover
                                : DS.Color.modelActionBorder,
                            lineWidth: DS.Border.standard
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.VoiceModels.actionCornerRadius, style: .continuous))
        }
        .buttonStyle(ModelActionInteractionStyle())
        .animation(DS.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ModelActionInteractionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed
                    ? DS.Material.buttonPressedScale
                    : DS.Material.buttonRestScale
            )
            .animation(
                configuration.isPressed ? DS.Motion.press : DS.Motion.release,
                value: configuration.isPressed
            )
    }
}

private struct DownloadProgress: View {
    let fraction: Double
    let phase: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(DS.Color.textPrimary)

            HStack {
                Text(phase)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download progress: \(phase), \(Int(fraction * 100)) percent")
    }
}

private struct ModelTechnicalDetails: View {
    let model: VoiceModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Grid(horizontalSpacing: DS.Space.wide, verticalSpacing: DS.Space.snug) {
                GridRow {
                    detail(label: "Provider", value: model.provider)
                    detail(label: "Runtime", value: model.runtime)
                }
                GridRow {
                    detail(
                        label: "Mode",
                        value: model.isApple ? "Native streaming" : "Incremental decoding with live preview"
                    )
                    detail(label: "Languages", value: model.languages.joined(separator: ", "))
                }
                GridRow {
                    detail(label: "Download", value: model.downloadSize)
                    detail(label: "Disk usage", value: model.diskSize)
                }
                GridRow {
                    detail(label: "Processing", value: "On your Mac")
                    detail(label: "Model files", value: model.isApple ? "System managed" : "Downloaded separately")
                }
            }

            Text("Sizes are estimates. macOS manages Apple Speech assets.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)

            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text("Technical attribution")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Text(model.attribution)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Technical details for \(model.name)")
    }

    private func detail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.hair) {
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
            Text(value)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
