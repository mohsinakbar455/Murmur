import SwiftUI

/// Thin adapter that hosts MurmurVoicePill and bridges it to DictationController and Murmur's Lucide icon system.
struct HUDView: View {
    @Bindable var controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
    }

    var body: some View {
        MurmurVoicePill(
            snapshot: controller.hudAdapter.snapshot,
            onStop: { [weak controller] in
                controller?.stopButtonRecording()
            },
            onDismiss: { [weak controller] in
                controller?.dismissHUDError()
            },
            symbol: { symbol in
                symbolView(for: symbol)
            }
        )
        .tint(DS.Color.accent)
        .shadow(
            color: DS.Shadow.elevated.color,
            radius: DS.Shadow.elevated.radius,
            x: DS.Shadow.elevated.x,
            y: DS.Shadow.elevated.y
        )
        .padding(DS.HUD.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private func symbolView(for symbol: MurmurHUDSymbol) -> some View {
        switch symbol {
        case .mic:
            LucideIcon(.mic, size: DS.HUD.statusIconSize)
        case .check:
            LucideIcon(.check, size: DS.HUD.statusIconSize)
        case .circleAlert:
            LucideIcon(.circleAlert, size: DS.HUD.statusIconSize)
        case .x:
            LucideIcon(.x, size: DS.HUD.statusIconSize)
        }
    }
}
