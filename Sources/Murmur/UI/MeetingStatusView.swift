import SwiftUI

/// Can be mounted in the app shell, menu bar, or a nonactivating recording panel.
struct MeetingStatusView: View {
    @State private var controller = MeetingController.shared
    var body: some View {
        if controller.isBusy {
            HStack(spacing: 10) {
                if controller.isRecording { Circle().fill(DS.Color.recordRed).frame(width: 8, height: 8) }
                else { ProgressView().controlSize(.small) }
                Text(label).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                if controller.isRecording {
                    Button("Stop") { Task { await controller.stop() } }.buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("Stop meeting recording")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(DS.Color.textPrimary)
            .background(DS.Color.cardElevated, in: Capsule())
            .overlay(Capsule().stroke(DS.Color.border))
            .accessibilityElement(children: .contain)
        }
    }
    private var label: String {
        switch controller.state {
        case .idle: ""
        case .preparing: "Preparing meeting…"
        case .recording: "Meeting · \(MeetingExport.clock(controller.elapsed))"
        case .finishing: "Finishing transcript…"
        }
    }
}
