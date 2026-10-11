import AppKit
import SwiftUI

/// Meeting recording must remain visible when the main window and dictation pill are closed.
@MainActor
final class MeetingPanelController {
    static let shared = MeetingPanelController()
    var onOpen: (() -> Void)?
    private let panel: MeetingRecordingPanel

    private init() {
        panel = MeetingRecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 90),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrameAutosaveName("MurmurMeetingRecorder")
        panel.contentView = NSHostingView(rootView: MeetingPanelContent { [weak self] in self?.openMeeting() })
        panel.setAccessibilityLabel("Murmur meeting recorder")
    }

    /// Called when MeetingController.state changes. SwiftUI observes elapsed and source itself.
    func sync() {
        guard MeetingController.shared.isBusy else { panel.orderOut(nil); return }
        if !panel.isVisible {
            let restored = panel.setFrameUsingName("MurmurMeetingRecorder")
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
            if !restored || !visible, let screen = NSScreen.main ?? NSScreen.screens.first {
                let bounds = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: bounds.maxX - panel.frame.width - 24, y: bounds.minY + 24))
            }
        }
        panel.orderFrontRegardless()
    }

    private func openMeeting() {
        NSApp.activate(ignoringOtherApps: true)
        if let onOpen { onOpen() }
        else {
            NSApp.windows.first(where: { $0 !== panel && $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }
}

private final class MeetingRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct MeetingPanelContent: View {
    @State private var controller = MeetingController.shared
    let onOpen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: controller.isRecording ? "record.circle.fill" : "waveform")
                    .foregroundStyle(controller.isRecording ? DS.Color.recordRed : DS.Color.accent)
                Text(status).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 6)
                Button("Open", action: onOpen).buttonStyle(.plain).foregroundStyle(DS.Color.textSecondary)
                    .accessibilityLabel("Open meeting transcript")
                if controller.isRecording {
                    Button("Stop") { Task { await controller.stop() } }
                        .buttonStyle(.borderedProminent).tint(DS.Color.accent).foregroundStyle(DS.Color.textOnAccent)
                        .controlSize(.small).accessibilityLabel("Stop meeting recording")
                } else { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(DS.Color.accent).font(.system(size: 9))
                Text(source).font(.system(size: 11)).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "hand.draw").font(.system(size: 10)).foregroundStyle(DS.Color.textTertiary).help("Drag to reposition")
            }
        }
        .padding(14).frame(width: 350, height: 90)
        .foregroundStyle(DS.Color.textPrimary)
        .background(DS.Color.cardElevated, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DS.Color.accent.opacity(0.35)))
    }
    private var source: String {
        controller.activeMeetingID.flatMap { controller.store.meeting($0)?.source } ?? "Preparing local recording"
    }
    private var status: String {
        switch controller.state {
        case .idle: "Meeting saved"
        case .preparing: "Preparing meeting…"
        case .recording: "Meeting · \(MeetingExport.clock(controller.elapsed))"
        case .finishing: "Finishing transcript…"
        }
    }
}
