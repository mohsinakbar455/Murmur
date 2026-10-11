import SwiftUI
import MurmurDictionary
import AppKit

/// Dashboard view for Murmur displaying system status, statistics, and recent dictations.
/// Pixel-accurately crafted to match the reference dark UI design.
struct DashboardView: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared
    @State private var isConfirmingClear = false
    @State private var isDeleteHovered = false
    @State private var historySearch = ""
    @State private var editingRun: DictationRun?

    init(controller: DictationController) {
        self.controller = controller
    }

    // Computed statistics
    private var totalRuns: Int {
        store.runs.count
    }

    private var totalWords: Int {
        store.runs.reduce(0) { total, run in
            total + run.text.split { $0.isWhitespace || $0.isPunctuation }.count
        }
    }

    private var totalAudioSeconds: Double {
        store.runs.reduce(0) { $0 + $1.audioSeconds }
    }

    private var avgLatencySeconds: Double {
        guard !store.runs.isEmpty else { return 0 }
        let total = store.runs.reduce(0) { $0 + $1.processSeconds }
        return total / Double(store.runs.count)
    }

    private var estimatedTimeSavedMinutes: Double {
        let wpm = Double(max(10, settings.typingWPM))
        let typingMinutes = Double(totalWords) / wpm
        let speakingMinutes = totalAudioSeconds / 60.0
        return max(0, typingMinutes - speakingMinutes)
    }

    private var recentRuns: [DictationRun] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.runs.reversed().filter { run in
            query.isEmpty || run.text.localizedStandardContains(query)
                || (run.rawText?.localizedStandardContains(query) ?? false)
                || (run.deliveredText?.localizedStandardContains(query) ?? false)
                || run.engine.localizedStandardContains(query)
        }
    }

    private var unsavedResult: TextProcessingResult? {
        settings.saveHistory ? nil : controller.lastResult
    }

    private var showsUnsavedResult: Bool {
        guard let result = unsavedResult else { return false }
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || result.text.localizedStandardContains(query)
    }

    private var recentResultCount: Int {
        recentRuns.count + (showsUnsavedResult ? 1 : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Dashboard header and live dictation indicator
                headerSection

                if !controller.isHotkeyReady {
                    HStack {
                        Label("Murmur needs Accessibility access for its keyboard shortcut.", systemImage: "keyboard.badge.ellipsis")
                            .font(DS.Font.body)
                        Spacer()
                        Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
                    }
                    .padding(DS.Space.roomy)
                    .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                }

                if !VoiceModelManager.shared.isModelInstalled(id: settings.selectedModelID) {
                    HStack {
                        Label("Download your selected speech model to begin.", systemImage: "arrow.down.circle")
                            .font(DS.Font.body)
                        Spacer()
                        Button("Choose model") { NotificationCenter.default.post(name: .murmurNavigate, object: SidebarDestination.models) }
                    }
                    .padding(DS.Space.roomy).background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                }
                // Flat horizontal statistics row
                statisticsRow

                // Recent dictations
                recentDictationsSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .background(DS.Color.canvas)
        .sheet(item: $editingRun) { run in
            DictationCorrectionSheet(run: run)
        }
    }

    // MARK: - Dashboard Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Dashboard" : "Welcome back, \(settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines))")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)

                Text("Private, on-device dictation from any app on your Mac.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: 0x8E929E))
            }

            Spacer(minLength: 24)

            dictationPill
        }
    }

    private var dictationPill: some View {
        DashboardWaveform(
            level: controller.level,
            isActive: controller.state == .starting || controller.state == .listening,
            isProcessing: controller.state == .finishing
        )
        .frame(width: DS.Dashboard.waveformGraphWidth, height: DS.Dashboard.waveformGraphHeight)
        .frame(width: DS.Dashboard.waveformDisplayWidth, height: DS.Dashboard.waveformDisplayHeight)
        .background(DS.Color.cardElevated)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dictationStatus)
        .help(dictationStatus)
    }

    private var dictationStatus: String {
        if !controller.isHotkeyReady {
            return "Keyboard shortcut unavailable. Grant Murmur Accessibility access in System Settings."
        }
        switch controller.state {
        case .idle:
            switch settings.recordingMode {
            case .holdToTalk:
                return "Ready. Hold \(settings.shortcut.displayName) to dictate."
            case .toggle:
                return "Ready. Press \(settings.shortcut.displayName) to start dictation."
            }
        case .starting, .listening:
            return "Recording"
        case .finishing:
            return "Transcribing"
        case .error(let message):
            return "Microphone unavailable. \(message) Check microphone permissions in System Settings."
        }
    }

    // MARK: - Flat Horizontal Statistics Row

    private var statisticsRow: some View {
        HStack(spacing: 0) {
            statItem(
                lucide: .fileText,
                value: "\(totalWords)",
                label: "Words Dictated",
                color: DS.Color.metricWords
            )

            statDivider

            statItem(
                lucide: .mic,
                value: DashboardMetrics.spokenAudio(totalAudioSeconds),
                label: "Spoken Audio",
                color: DS.Color.metricAudio
            )

            statDivider

            statItem(
                lucide: .zap,
                value: String(format: "%.2f sec", avgLatencySeconds),
                label: "Avg. Latency",
                color: DS.Color.metricLatency
            )

            statDivider

            statItem(
                lucide: .clock,
                value: String(format: "%.1f min", estimatedTimeSavedMinutes),
                label: "Time Saved",
                color: DS.Color.metricTimeSaved
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.standard)
        )
    }

    private func statItem(
        lucide: LucideIcon.Name,
        value: String,
        label: String,
        color: Color
    ) -> some View {
        HStack(spacing: DS.Space.base) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(color.opacity(DS.Dashboard.statisticIconSurfaceOpacity))

                LucideIcon(lucide, size: DS.Dashboard.statisticIconSize)
                    .foregroundStyle(color)
            }
            .frame(width: DS.Dashboard.statisticIconFrame, height: DS.Dashboard.statisticIconFrame)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(
                        color.opacity(DS.Dashboard.statisticIconBorderOpacity),
                        lineWidth: DS.Border.hairline
                    )
            )

            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text(value)
                    .font(DS.Font.statNumber)
                    .foregroundStyle(DS.Color.textPrimary)
                    .monospacedDigit()

                Text(label)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(DS.Color.border)
            .frame(width: 1, height: 32)
    }

    // MARK: - Recent Dictations Section

    private var recentDictationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header & Delete Button
            HStack {
                Text("Recent Dictations")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.textPrimary)

                Spacer()

                Button {
                    if !store.runs.isEmpty {
                        isConfirmingClear = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.trash2, size: 13)
                        Text("Clear All")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.runs.isEmpty ? Color(hex: 0x5A5F6E) : (isDeleteHovered ? Color.white : Color(hex: 0x8E929E)))
                }
                .buttonStyle(.plain)
                .disabled(store.runs.isEmpty)
                .onHover { isDeleteHovered = $0 }
                .help(store.runs.isEmpty ? "No dictations to delete" : "Clear all dictation history")
                .accessibilityLabel("Clear all dictation history")
            }

            if !store.runs.isEmpty || unsavedResult != nil {
                HStack(spacing: DS.Space.snug) {
                    LucideIcon(.search, size: 15).foregroundStyle(DS.Color.textSecondary)
                    TextField("Search dictations…", text: $historySearch)
                        .textFieldStyle(.plain).font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .accessibilityLabel("Search dictations by transcript or speech engine")
                    if !historySearch.isEmpty {
                        Text("\(recentResultCount) result\(recentResultCount == 1 ? "" : "s")")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        Button { historySearch = "" } label: {
                            LucideIcon(.xmark, size: 14).foregroundStyle(DS.Color.textSecondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Clear history search")
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, DS.Space.base)
                .frame(height: DS.Layout.settingsSearchHeight)
                .background(DS.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: DS.Border.hairline))
            }

            // Clean Native macOS Transcript Rows
            if store.runs.isEmpty && unsavedResult == nil {
                VStack(spacing: 12) {
                    LucideIcon(.mic, size: 28)
                        .foregroundStyle(Color(hex: 0x64748B))

                    Text("No dictations yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Text("Use your dictation shortcut anywhere on your Mac to get started.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: 0x8E929E))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(hex: 0x181A1F))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: 0x262830), lineWidth: 1)
                )
            } else if recentResultCount == 0 {
                VStack(spacing: DS.Space.snug) {
                    Text("No matching dictations").font(DS.Font.bodyEmphasis)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Search a word from the saved or original transcript, or a speech engine name.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    Button("Clear Search") { historySearch = "" }
                }
                .frame(maxWidth: .infinity).padding(.vertical, DS.Space.panel)
            } else {
                LazyVStack(spacing: DS.Dashboard.transcriptCardSpacing) {
                    if showsUnsavedResult, let result = unsavedResult {
                        DashboardUnsavedTranscriptRow(result: result)
                    }
                    ForEach(recentRuns) { run in
                        DashboardTranscriptRow(
                            run: run,
                            onEdit: { editingRun = run },
                            onDelete: {
                                withAnimation(DS.Motion.transition) {
                                    RunLog.delete(run)
                                }
                            }
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    RunLog.clear()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.runs.count) dictation records. This cannot be undone.")
        }
    }
}

// MARK: - Native macOS Clean Transcript Row

private struct DashboardUnsavedTranscriptRow: View {
    let result: TextProcessingResult

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(result.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    Text("History is off · not saved")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.Color.textSecondary)
                    if let reason = result.fallbackReason {
                        LucideIcon(.info, size: 12)
                            .foregroundStyle(DS.Color.warningAmber)
                            .help(reason)
                            .accessibilityLabel("Cleanup fallback: \(reason)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashboardTranscriptActionButton(
                icon: .copy,
                hoverForeground: DS.Color.accent,
                hoverBackground: DS.Color.accentSoft,
                help: "Copy transcript to clipboard",
                accessibilityLabel: "Copy transcript"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.text, forType: .string)
            }
        }
        .padding(DS.Dashboard.transcriptCardPadding)
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.standard)
        )
    }
}

private struct DashboardTranscriptRow: View {
    let run: DictationRun
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var didCopy = false

    private static func formattedTimestamp(for date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return timeString
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, \(timeString)"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d, "
            return df.string(from: date) + timeString
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Left: Primary Transcript text and metadata
            VStack(alignment: .leading, spacing: 5) {
                Text(run.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    Text(Self.formattedTimestamp(for: run.date))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x7E8391))

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0x484C56))

                    Text(String(format: "%.2fs latency", run.processSeconds))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x7E8391))

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0x484C56))

                    Text(String(format: "%.1fs audio", run.audioSeconds))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: 0x7E8391))

                    if run.deliveredText != nil {
                        Text("Edited").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                    if run.fallbackReason != nil {
                        LucideIcon(.info, size: 12).foregroundStyle(DS.Color.warningAmber)
                            .help("Cleanup used a fallback. Open Edit for processing details.")
                            .accessibilityLabel("Cleanup fallback; processing details available")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: direct transcript actions
            HStack(spacing: DS.Space.snug) {
                Button("Edit", action: onEdit)
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary)
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.snug)
                    .frame(height: DS.Dashboard.transcriptActionSize)
                    .background(DS.Color.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                    .help("Review the original transcript, edit saved text, or remember a correction")
                    .accessibilityLabel("Review and correct transcript")

                DashboardTranscriptActionButton(
                    icon: didCopy ? .check : .copy,
                    isActive: didCopy,
                    hoverForeground: DS.Color.accent,
                    hoverBackground: DS.Color.accentSoft,
                    help: didCopy ? "Copied to clipboard" : "Copy transcript to clipboard",
                    accessibilityLabel: didCopy ? "Copied" : "Copy transcript"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(
                            for: .seconds(DS.Dashboard.transcriptCopyConfirmationDuration)
                        )
                        didCopy = false
                    }
                }

                DashboardTranscriptActionButton(
                    icon: .trash2,
                    role: .destructive,
                    hoverForeground: DS.Color.textPrimary,
                    hoverBackground: DS.Color.cardSelected,
                    help: "Delete this transcript",
                    accessibilityLabel: "Delete transcript",
                    action: onDelete
                )
            }
        }
        .padding(DS.Dashboard.transcriptCardPadding)
        .background(isHovered ? DS.Color.cardSelected : DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.standard)
        )
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
    }
}

private struct DashboardTranscriptActionButton: View {
    let icon: LucideIcon.Name
    var role: ButtonRole? = nil
    var isActive = false
    let hoverForeground: Color
    let hoverBackground: Color
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            LucideIcon(icon, size: DS.Dashboard.transcriptActionIconSize)
                .frame(
                    width: DS.Dashboard.transcriptActionSize,
                    height: DS.Dashboard.transcriptActionSize
                )
                .background(isHovered ? hoverBackground : DS.Color.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(
                            isHovered ? DS.Color.borderGlass : DS.Color.border,
                            lineWidth: DS.Border.standard
                        )
                )
                .foregroundStyle(
                    isActive || isHovered ? hoverForeground : DS.Color.textSecondary
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .scaleEffect(
                    reduceMotion || !isHovered
                        ? DS.Dashboard.transcriptActionRestScale
                        : DS.Dashboard.transcriptActionHoverScale
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : DS.Motion.hover, value: isHovered)
    }
}

// MARK: - Instrument Signal Visualizer

private struct DashboardWaveform: View {
    let level: Float
    let isActive: Bool
    let isProcessing: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / DS.Dashboard.waveformFramesPerSecond,
                paused: !isActive && !isProcessing
            )
        ) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(DS.Dashboard.waveformBaselineOpacity))
                    .frame(height: DS.Dashboard.waveformBaselineHeight)

                HStack(alignment: .center, spacing: DS.Dashboard.waveformBarSpacing) {
                    ForEach(0..<DS.Dashboard.waveformBarCount, id: \.self) { index in
                        Capsule()
                            .fill(barColor(for: index, at: t))
                            .frame(
                                width: DS.Dashboard.waveformBarWidth,
                                height: barHeight(for: index, at: t)
                            )
                    }
                }
            }
        }
    }

    /// Normalized distance from center: 0.0 at center, 1.0 at outer edges
    private func normalizedDistance(for index: Int) -> Double {
        let center = Double(DS.Dashboard.waveformBarCount - 1) / 2.0
        return abs(Double(index) - center) / center
    }

    private func barColor(for index: Int, at time: TimeInterval) -> Color {
        let d = normalizedDistance(for: index)

        if isActive {
            let opacity = DS.Dashboard.waveformStrongOpacity
                - d * (DS.Dashboard.waveformStrongOpacity - DS.Dashboard.waveformSecondaryOpacity)
            return DS.Color.recordRed.opacity(opacity)
        } else if isProcessing {
            let pulse = (
                sin(
                    time * DS.Dashboard.waveformProcessingSpeed
                    + Double(index) * DS.Dashboard.waveformProcessingPhaseStep
                ) + 1.0
            ) / 2.0
            let opacity = DS.Dashboard.waveformMutedOpacity
                + pulse * (DS.Dashboard.waveformStrongOpacity - DS.Dashboard.waveformMutedOpacity)
            return DS.Color.infoBlue.opacity(opacity)
        } else {
            return d < DS.Dashboard.waveformAccentRadius
                ? DS.Color.accent.opacity(DS.Dashboard.waveformStrongOpacity)
                : DS.Color.textTertiary.opacity(DS.Dashboard.waveformMutedOpacity)
        }
    }

    private func barHeight(for index: Int, at time: TimeInterval) -> CGFloat {
        let d = normalizedDistance(for: index)
        let envelope = CGFloat(
            pow(
                cos(d * .pi / DS.Dashboard.waveformEnvelopeDivisor),
                DS.Dashboard.waveformEnvelopePower
            )
        )
        let minimum = DS.Dashboard.waveformBarWidth

        if isActive {
            let signal = CGFloat(
                abs(
                    sin(
                        time * DS.Dashboard.waveformActiveSpeed
                        + Double(index) * DS.Dashboard.waveformActivePhaseStep
                    )
                )
            )
            let amplitude = max(
                DS.Dashboard.waveformActiveMinimumAmplitude,
                min(CGFloat(level) * DS.Dashboard.waveformActiveGain, 1)
            )
            let edgeFade = DS.Dashboard.waveformActiveEdgeFloor
                + envelope * DS.Dashboard.waveformActiveEdgeGain
            return minimum + amplitude * edgeFade
                * (DS.Dashboard.waveformActiveBaseHeight + signal * DS.Dashboard.waveformActiveSignalHeight)
        } else if isProcessing {
            let signal = CGFloat(
                (
                    sin(
                        time * DS.Dashboard.waveformProcessingSpeed
                        + Double(index) * DS.Dashboard.waveformProcessingPhaseStep
                    ) + 1.0
                ) / 2.0
            )
            return minimum + DS.Dashboard.waveformProcessingBaseHeight
                + signal * DS.Dashboard.waveformProcessingSignalHeight
        } else {
            // A quiet, fixed signal trace instead of a tall static bell curve.
            let signal = CGFloat(
                abs(sin(Double(index) * DS.Dashboard.waveformIdlePhaseStep))
            )
            return minimum + DS.Dashboard.waveformIdleBaseHeight
                + envelope * (
                    DS.Dashboard.waveformIdleEnvelopeHeight
                    + signal * DS.Dashboard.waveformIdleSignalHeight
                )
        }
    }
}
