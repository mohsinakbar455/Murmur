import AppKit
import SwiftUI

/// Custom NSHostingView that allows the Stop and Dismiss controls to receive clicks
/// immediately without requiring an initial click to activate the panel.
@MainActor
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// The non-activating floating capsule panel that displays MurmurVoicePill.
///
/// The single most important property here is that this panel **never becomes key**.
/// If it did, the user's text field would lose focus and `TextInjector` would have
/// nothing to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false`.
@MainActor
final class HUDPanel: NSPanel {
    private var lockedScreen: NSScreen?
    private var currentContentSize = CGSize(width: DS.HUD.compactWidth, height: DS.HUD.height)
    private var resizeTask: Task<Void, Never>?
    private var isPresented = false
    private var presentationGeneration = 0

    init(controller: DictationController) {
        let initialWidth = DS.HUD.compactWidth + DS.HUD.outerPadding * 2
        let initialHeight = DS.HUD.height + DS.HUD.outerPadding * 2

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = FirstMouseHostingView(rootView: HUDView(controller: controller))

        controller.hudAdapter.onFrameChange = { [weak self] contentSize in
            self?.updateSize(for: contentSize)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Identifies the screen containing the mouse cursor or falling back to main screen.
    private func determineTargetScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// Positions the visible capsule 20 points above the usable bottom edge of the locked display,
    /// centered horizontally.
    func reposition() {
        let screen = lockedScreen ?? determineTargetScreen()
        lockedScreen = screen

        let visible = screen.visibleFrame
        let targetWindowWidth = currentContentSize.width + DS.HUD.outerPadding * 2
        let targetWindowHeight = currentContentSize.height + DS.HUD.outerPadding * 2

        setFrame(
            NSRect(
                x: visible.midX - targetWindowWidth / 2,
                y: visible.minY + DS.HUD.outerPadding,
                width: targetWindowWidth,
                height: targetWindowHeight
            ),
            display: true
        )
    }

    /// Keeps the waveform centered above the bottom edge when a status message changes its size.
    func updateSize(for contentSize: CGSize) {
        guard contentSize != currentContentSize else { return }
        let oldSize = currentContentSize
        currentContentSize = contentSize

        let targetWindowWidth = contentSize.width + DS.HUD.outerPadding * 2
        let targetWindowHeight = currentContentSize.height + DS.HUD.outerPadding * 2
        let screen = lockedScreen ?? determineTargetScreen()
        let visible = screen.visibleFrame
        let targetRect = NSRect(
            x: visible.midX - targetWindowWidth / 2,
            y: visible.minY + DS.HUD.outerPadding,
            width: targetWindowWidth,
            height: targetWindowHeight
        )

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion || contentSize.width > oldSize.width || contentSize.height > oldSize.height {
            resizeTask?.cancel()
            resizeTask = nil
            setFrame(targetRect, display: true)
        } else {
            resizeTask?.cancel()
            resizeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(DS.HUD.resizeDelayMilliseconds))
                guard let self, !Task.isCancelled else { return }
                self.setFrame(targetRect, display: true)
            }
        }
    }

    func present() {
        // Meter updates must never restart an in-progress fade from alpha zero.
        guard !isPresented else { return }
        isPresented = true
        presentationGeneration += 1
        if lockedScreen == nil {
            lockedScreen = determineTargetScreen()
        }
        reposition()
        // Resume an interrupted fade-out at its current opacity instead of flashing off.
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DS.HUD.panelTransitionDuration
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DS.HUD.panelTransitionDuration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                // A new recording may have started while this fade-out was finishing.
                guard let self, !self.isPresented,
                      self.presentationGeneration == generation else { return }
                self.orderOut(nil)
                self.lockedScreen = nil
                self.resizeTask?.cancel()
                self.resizeTask = nil
            }
        }
    }
}
