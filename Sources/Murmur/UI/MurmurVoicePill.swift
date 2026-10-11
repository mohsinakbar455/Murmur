import SwiftUI

/// Semantic names for an adapter to the app's EXISTING Lucide renderer.
/// This file intentionally does not guess Lucide.swift's unknown public API.
enum MurmurHUDSymbol {
    case mic, check, circleAlert, x
}

@MainActor
struct MurmurVoicePill<Symbol: View>: View {
    let snapshot: MurmurHUDSnapshot
    let onStop: () -> Void
    let onDismiss: () -> Void
    private let symbol: (MurmurHUDSymbol) -> Symbol

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var processingDate = Date()

    init(
        snapshot: MurmurHUDSnapshot,
        onStop: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        @ViewBuilder symbol: @escaping (MurmurHUDSymbol) -> Symbol
    ) {
        self.snapshot = snapshot
        self.onStop = onStop
        self.onDismiss = onDismiss
        self.symbol = symbol
    }

    var body: some View {
        Group {
            if snapshot.isVisible {
                content
                    .padding(.horizontal, DS.HUD.horizontalPadding)
                    .frame(width: CGFloat(snapshot.pillWidth), height: CGFloat(MurmurHUDSnapshot.pillHeight))
                    .modifier(MurmurHUDMaterial())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(snapshot.phase.accessibilityTitle)
            }
        }
        // The native panel owns visibility fades. Only animate capsule size here.
        .animation(reduceMotion ? nil : DS.Motion.panel,
                   value: snapshot.pillWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.phase {
        case .hidden:
            EmptyView()

        case .listening:
            Button(action: onStop) {
                HStack(spacing: DS.Space.snug) {
                    waveform(levels: snapshot.levels, color: DS.Color.hudActivity)
                    if !snapshot.liveText.isEmpty {
                        Text(snapshot.liveText).font(DS.Font.label)
                            .foregroundStyle(DS.Color.hudContent).lineLimit(1).truncationMode(.head)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Stop recording and transcribe")
            .help("Stop recording and transcribe")

        case .starting:
            processingWaveform

        case .transcribing:
            processingWaveform

        case .cleaning:
            statusRow("Cleaning up", symbolName: .mic)

        case .delivering:
            processingWaveform

        case .completed:
            glyph(.check)

        case .noSpeech:
            statusRow("No speech detected", symbolName: .mic)

        case .failed:
            HStack(spacing: DS.HUD.statusSpacing) {
                glyph(.circleAlert)
                Text("Couldn't transcribe")
                    .font(DS.Font.label)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    glyph(.x)
                        .frame(
                            width: DS.HUD.dismissButtonWidth,
                            height: DS.HUD.dismissButtonHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Dismiss transcription error")
            }
            .help(snapshot.errorMessage ?? "Transcription failed. Try recording again.")
        }
    }

    private func waveform(levels: [Double], color: Color) -> some View {
        HStack(alignment: .center, spacing: DS.HUD.waveformBarSpacing) {
            ForEach(0..<DS.HUD.waveformBarCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(
                        width: DS.HUD.waveformBarWidth,
                        height: DS.HUD.waveformMinimumBarHeight
                            + CGFloat(levels[index]) * DS.HUD.waveformBarTravel
                    )
            }
        }
        .frame(height: DS.HUD.waveformHeight)
        .animation(
            reduceMotion ? nil : .linear(duration: DS.HUD.waveformAnimationDuration),
            value: levels
        )
        .accessibilityHidden(true)
    }

    // TimelineView's callback crashed in Swift's main-executor check on macOS 27.
    // Drive this short-lived animation from a cancellable main-actor task instead.
    private var processingWaveform: some View {
        waveform(
            levels: processingLevels(at: processingDate),
            color: DS.Color.hudActivity
        )
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(DS.HUD.processingFrameInterval))
                } catch {
                    break
                }
                processingDate = Date()
            }
        }
    }

    private func processingLevels(at date: Date) -> [Double] {
        guard !reduceMotion else {
            return Array(
                repeating: DS.HUD.processingRestingLevel,
                count: DS.HUD.waveformBarCount
            )
        }

        let time = date.timeIntervalSinceReferenceDate
        let center = Double(DS.HUD.waveformBarCount - 1) / 2
        return (0..<DS.HUD.waveformBarCount).map { index in
            let distance = abs(Double(index) - center) / max(center, 1)
            let envelope = DS.HUD.processingEnvelopeFloor
                + (1 - distance) * DS.HUD.processingEnvelopeGain
            let pulse = (sin(
                time * DS.HUD.processingSpeed
                    + Double(index) * DS.HUD.processingPhaseStep
            ) + 1) / 2
            return envelope * (
                DS.HUD.processingMinimumLevel
                    + pulse * DS.HUD.processingLevelRange
            )
        }
    }

    private func glyph(_ name: MurmurHUDSymbol) -> some View {
        symbol(name)
            .frame(width: DS.HUD.statusIconSize, height: DS.HUD.statusIconSize)
            .foregroundStyle(DS.Color.hudActivity)
            .accessibilityHidden(true)
    }

    private func statusRow(
        _ text: String,
        symbolName: MurmurHUDSymbol
    ) -> some View {
        HStack(spacing: DS.HUD.statusSpacing) {
            glyph(symbolName)
            Text(text)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.hudContent)
                .lineLimit(1)
        }
    }
}
