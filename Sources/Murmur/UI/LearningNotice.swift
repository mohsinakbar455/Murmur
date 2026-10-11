import AppKit
import SwiftUI

/// Brief, nonactivating feedback keeps learning visible without interrupting typing.
@MainActor
final class LearningNotice {
    static let shared = LearningNotice()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    func show(_ message: String, changeID: UUID) {
        dismissal?.cancel()
        panel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 70),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HStack(spacing: DS.Space.base) {
            Text(message).font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textPrimary).lineLimit(2)
            Spacer()
            Button("Undo") { [weak panel] in
                if LearnedTermStore.shared.changeID == changeID { LearnedTermStore.shared.undo() }
                panel?.orderOut(nil)
            }
        }.padding(DS.Space.roomy).frame(width: 340, height: 70)
            .background(DS.Color.card, in: RoundedRectangle(cornerRadius: DS.Radius.card)))
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 360, y: frame.minY + 24))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            panel.orderOut(nil)
        }
    }
}
