import AppKit
import SwiftUI
import Testing
@testable import Murmur

@Suite("HUD panel presentation", .serialized)
@MainActor
struct HUDPanelTests {
    @Test("Processing waveform renders through repeated SwiftUI updates")
    func processingWaveformRendering() async throws {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: MurmurVoicePill(
            snapshot: MurmurHUDSnapshot(phase: .transcribing),
            onStop: {},
            onDismiss: {},
            symbol: { _ in Image(systemName: "mic.fill") }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        for _ in 0..<40 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(view.frame.width > 0)
    }

    @Test("Meter updates do not restart the panel fade")
    func repeatedPresentation() async throws {
        _ = NSApplication.shared
        let controller = DictationController()
        let panel = HUDPanel(controller: controller)
        defer { panel.orderOut(nil) }
        panel.present()
        var samples: [CGFloat] = []
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            samples.append(panel.alphaValue)
            panel.present()
        }
        #expect(samples.last! > 0.99)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 })
    }

    @Test("An old dismissal cannot hide a newly presented recording")
    func restartDuringDismissal() async throws {
        _ = NSApplication.shared
        let controller = DictationController()
        let panel = HUDPanel(controller: controller)
        defer { panel.orderOut(nil) }
        panel.present()
        try await Task.sleep(for: .milliseconds(250))
        panel.dismiss()
        try await Task.sleep(for: .milliseconds(50))
        let opacityBeforeRestart = panel.alphaValue
        panel.present()
        #expect(panel.alphaValue >= opacityBeforeRestart)
        try await Task.sleep(for: .milliseconds(300))
        #expect(panel.isVisible)
        #expect(panel.alphaValue > 0.99)
        #expect(!panel.canBecomeKey)
    }
}
