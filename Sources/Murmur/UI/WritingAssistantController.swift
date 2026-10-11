import AppKit
import ApplicationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class WritingAssistantController {
    static weak var current: WritingAssistantController?
    var instruction = ""
    var source = ""
    private(set) var output = ""
    private(set) var status = ""
    private(set) var busy = false
    private(set) var listening = false
    private(set) var isOpen = false
    private(set) var hasResult = false
    private(set) var needsReview = false
    private(set) var appName = "Pasted text"
    private(set) var selectedCount = 0
    var composeMode = false
    private(set) var hasTarget = false
    private(set) var selectionUnavailable = false
    @ObservationIgnored private var capturing = false
    @ObservationIgnored private var badgeSelected: Bool?
    @ObservationIgnored private var observedField: AXUIElement?
    private(set) var receipt: WritingSelection.Receipt?
    private(set) var lastReceipt: WritingSelection.Receipt?
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    private let dictation: DictationController
    @ObservationIgnored private var badge: WritingAssistantPanel?
    @ObservationIgnored private var panel: WritingAssistantPanel?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var target: WritingSelection?
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var observedPID: pid_t?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var outsideClick: Any?
    @ObservationIgnored private var localClick: Any?

    init(dictation: DictationController) { self.dictation = dictation }

    var modelReady: Bool { WritingModelManager.shared.selectedModelURL != nil && LocalTextRuntime.runtimeAvailable }
    var canGenerate: Bool { modelReady && !busy && !listening && !selectionUnavailable }
    var canUndoLastEdit: Bool {
        guard let lastReceipt, let target else { return false }
        return target.pid == lastReceipt.selection.pid && CFEqual(target.element, lastReceipt.selection.element)
            && target.fingerprint.range == lastReceipt.caret
    }

    func start() {
        Self.current = self
        stopped = false
        watchPreference()
        syncEnabled()
    }

    private func watchPreference() {
        withObservationTracking { _ = Settings.shared.writingAssistantEnabled } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.syncEnabled()
                self.watchPreference()
            }
        }
    }

    private func syncEnabled() {
        monitor?.cancel(); monitor = nil
        if !Settings.shared.writingAssistantEnabled {
            close(); lastReceipt = nil; undoExpiry?.cancel(); undoExpiry = nil
            badge?.orderOut(nil); removeObserver()
            return
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do { try await Task.sleep(for: .milliseconds(750)) } catch { break }
            }
        }
    }

    func stop() {
        stopped = true
        lastReceipt = nil; undoExpiry?.cancel(); undoExpiry = nil
        monitor?.cancel(); monitor = nil
        close(); badge?.orderOut(nil); removeObserver()
    }

    private func removeObserver() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedPID = nil; observedField = nil
    }

    private func observe(_ pid: pid_t) {
        guard observedPID != pid else { return }
        removeObserver()
        var next: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            Task { @MainActor in WritingAssistantController.current?.refresh() }
        }, &next) == .success, let next else { return }
        observer = next; observedPID = pid
        let app = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedUIElementChangedNotification, kAXSelectedTextChangedNotification, kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(next, app, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
    }

    func refresh() {
        guard !stopped, Settings.shared.writingAssistantEnabled else {
            badge?.orderOut(nil)
            if isOpen { close() }
            return
        }
        if capturing { return }
        if isOpen {
            if target != nil && !Permissions.hasAccessibility { close(); return }
            if let target, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               pid != target.pid && pid != ProcessInfo.processInfo.processIdentifier { close() }
            return
        }
        guard Permissions.hasAccessibility, !dictation.state.isActive, !MeetingController.shared.isBusy,
              let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let field = WritingSelection.focused(in: app.processIdentifier), !WritingSelection.isSecure(field),
              WritingSelection.isTextEntry(field),
              let frame = WritingSelection.launcherFrame(of: field, in: app.processIdentifier) else {
            badge?.orderOut(nil)
            return
        }
        let hasSelection = (WritingSelection.range(of: field)?.length ?? 0) > 0
        observe(app.processIdentifier)
        if let observer, observedField == nil || !CFEqual(observedField!, field) {
            if let observedField {
                AXObserverRemoveNotification(observer, observedField, kAXSelectedTextChangedNotification as CFString)
            }
            AXObserverAddNotification(observer, field, kAXSelectedTextChangedNotification as CFString, nil)
            observedField = field
        }
        if badge == nil { badge = WritingAssistantPanel(size: CGSize(width: 32, height: 32), keyboard: false) }
        if badgeSelected != hasSelection || badge?.contentView == nil {
            badgeSelected = hasSelection
            badge?.contentView = FirstMouseHostingView(rootView: WritingAssistantBadge(selected: hasSelection) { [weak self] in self?.openSelection() })
        }
        let screen = NSScreen.screens.max { $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area } ?? NSScreen.main
        guard let screen else { return }
        var visible = frame.intersection(screen.visibleFrame)
        if let window = WritingSelection.attribute(kAXWindowAttribute, of: field),
           CFGetTypeID(window) == AXUIElementGetTypeID(),
           let windowFrame = WritingSelection.frame(of: unsafeDowncast(window, to: AXUIElement.self)) {
            visible = visible.intersection(windowFrame)
        }
        guard !visible.isNull, visible.width >= 32, visible.height >= 24 else { badge?.orderOut(nil); return }
        // Keep the launcher inside the visible editor, away from its scroll bar.
        badge?.setFrameOrigin(CGPoint(x: max(visible.minX, visible.maxX - 40), y: max(visible.minY, visible.minY + (min(visible.height, 40) - 32) / 2)))
        badge?.orderFrontRegardless()
    }

    func openSelection() {
        guard !isOpen, !capturing, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let field = WritingSelection.focused(in: app.processIdentifier),
              !WritingSelection.isSecure(field), WritingSelection.isTextEntry(field) else { return }
        // Resolve focus now: the launcher can lag behind a fast move between fields.
        capturing = true
        let id = UUID(); generation = id
        operation = Task { [weak self] in
            let captured = await WritingSelection.captureAutomatically(element: field, app: app)
            guard let self, self.generation == id, !Task.isCancelled else { captured?.lease?.stop(); return }
            self.capturing = false
            self.open(target: captured)
            if captured == nil {
                self.selectionUnavailable = true
                self.status = "Select text in your editor, then reopen Writing Assistant."
            }
        }
    }

    func openPastedText() {
        guard Settings.shared.writingAssistantEnabled else { return }
        open(target: nil)
    }

    private func open(target: WritingSelection?) {
        guard !isOpen, !dictation.state.isActive, !MeetingController.shared.isBusy else {
            target?.lease?.stop()
            return
        }
        self.target = target; hasTarget = target != nil; selectionUnavailable = false
        source = target?.fingerprint.text ?? ""
        selectedCount = source.split(whereSeparator: \.isWhitespace).count
        appName = target?.appName ?? "Pasted text"
        instruction = ""; output = ""; status = ""; receipt = nil; hasResult = false; needsReview = false; composeMode = false
        generation = UUID(); isOpen = true
        dictation.setWritingAssistantActive(true)
        let panelSize = CGSize(width: 328, height: modelReady ? 480 : 92)
        if panel == nil { panel = WritingAssistantPanel(size: panelSize, keyboard: true) }
        else { panel?.setContentSize(panelSize) }
        panel?.contentView = FirstMouseHostingView(rootView: WritingAssistantView(controller: self))
        let anchor = badge?.isVisible == true ? badge!.frame : CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let x = min(max(anchor.maxX - panelSize.width, bounds.minX), bounds.maxX - panelSize.width)
            let y = min(max(anchor.maxY + 6, bounds.minY), bounds.maxY - panelSize.height)
            panel?.setFrameOrigin(CGPoint(x: x, y: y))
        }
        badge?.orderOut(nil)
        panel?.orderFrontRegardless()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, let frame = self.panel?.frame, !frame.contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
            return event
        }
    }

    func close() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }; outsideClick = nil
        if let localClick { NSEvent.removeMonitor(localClick) }; localClick = nil
        generation = UUID()
        operation?.cancel(); operation = nil
        capturing = false
        target?.lease?.stop()
        if listening { dictation.cancelInstructionDictation() }
        listening = false; busy = false
        if isOpen { dictation.setWritingAssistantActive(false) }
        isOpen = false; panel?.orderOut(nil)
        target = nil; receipt = nil; source = ""; output = ""; instruction = ""; hasResult = false
    }

    func paste() {
        guard !busy, !hasTarget else { return }
        source = NSPasteboard.general.string(forType: .string) ?? ""
        status = source.isEmpty ? "Copy some text, then choose Paste text." : ""
    }

    func run(_ action: WritingAction) {
        guard canGenerate else { return }
        if action == .compose && instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composeMode = true; status = "Describe what to compose in the field above."; panel?.makeKey(); return
        }
        let action = action == .custom && composeMode ? WritingAction.compose : action
        do { _ = try WritingAssistantService.request(action: action, source: source, instruction: instruction) }
        catch { status = error.localizedDescription; return }
        let id = UUID(); generation = id
        let original = source, prompt = instruction, destination = target
        let profile = PersonalizationStore.shared.context(for: destination?.bundleID,
            styleID: action.personalizationStyleID)
        busy = true; status = "\(action.title)…"; output = ""; hasResult = false
        operation = Task { [weak self] in
            do {
                let result = try await WritingAssistantService.perform(action: action, source: original, instruction: prompt, profile: profile)
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.output = result
                if let destination {
                    self.panel?.orderOut(nil)
                    _ = await destination.waitForFocus()
                    guard self.generation == id, !Task.isCancelled else { return }
                    let delivery = await destination.replace(with: result)
                    guard self.generation == id, !Task.isCancelled else { return }
                    switch delivery {
                    case .applied(let receipt):
                        self.rememberUndo(receipt)
                        self.close()
                        self.refresh()
                        return
                    case .unchanged, .dispatched:
                        self.close()
                        self.refresh()
                        return
                    case .unavailable: self.status = "The selection changed. Select the text again and reopen Writing Assistant."
                    case .unverified: self.status = "Check your editor: replacement could not be confirmed."
                    }
                    self.panel?.orderFrontRegardless()
                } else { self.status = "Ready to copy." }
                self.hasResult = true; self.busy = false
            } catch let review as WritingReviewRequired {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.output = review.text
                self.status = "Review this change: \(review.reason) Your original text was kept."
                self.needsReview = destination != nil
                self.hasResult = true; self.busy = false
                self.panel?.orderFrontRegardless()
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.status = error.localizedDescription; self.busy = false
                self.panel?.orderFrontRegardless()
            }
        }
    }

    func applyReviewedResult() {
        guard needsReview, !busy, let target else { return }
        busy = true
        let id = generation
        operation = Task { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            _ = await target.waitForFocus()
            guard self.generation == id, !Task.isCancelled else { return }
            let result = await target.replace(with: self.output)
            guard self.generation == id, !Task.isCancelled else { return }
            switch result {
            case .applied(let receipt):
                self.rememberUndo(receipt); self.close(); self.refresh(); return
            case .unchanged, .dispatched:
                self.close(); self.refresh(); return
            case .unavailable: self.status = "The selection changed. Select the text again and reopen Writing Assistant."
            case .unverified: self.status = "Check your editor: replacement could not be confirmed."
            }
            self.needsReview = false; self.busy = false
            self.panel?.orderFrontRegardless()
        }
    }

    private func rememberUndo(_ receipt: WritingSelection.Receipt) {
        lastReceipt = receipt
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.lastReceipt = nil
        }
    }

    func undoLastEdit() {
        guard let previous = lastReceipt else { return }
        receipt = previous
        undo()
    }

    func undo() {
        guard let receipt, !busy else { return }
        busy = true
        let id = generation
        operation = Task { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            try? await Task.sleep(for: .milliseconds(120))
            guard self.generation == id, !Task.isCancelled else { return }
            let result = await WritingSelection.undo(receipt)
            guard self.generation == id, !Task.isCancelled else { return }
            switch result {
            case .applied, .unchanged, .dispatched:
                self.lastReceipt = nil; self.undoExpiry?.cancel(); self.undoExpiry = nil
                self.close(); self.refresh()
                return
            case .unavailable: self.status = "The editor changed. Use Copy original to restore it manually."
            case .unverified: self.status = "Check your editor: Undo could not be confirmed."
            }
            self.source = receipt.selection.fingerprint.text; self.output = receipt.replacement; self.hasResult = true
            self.receipt = nil; self.lastReceipt = nil; self.busy = false
            self.panel?.orderFrontRegardless()
        }
    }

    func copy(original: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(original ? source : output, forType: .string)
        status = original ? "Original copied." : "Result copied."
    }

    func toggleMicrophone() {
        guard !busy else { return }
        if listening { dictation.stopButtonRecording(); return }
        let id = generation
        let started = dictation.startInstructionDictation { [weak self] result in
            guard let self, self.generation == id else { return }
            self.listening = false
            switch result {
            case .success(let text): self.instruction = text; self.status = text.isEmpty ? "No speech detected. Try again." : "Instruction ready. Press Return to apply."
            case .failure(let error): self.status = error.localizedDescription
            }
        }
        listening = started
        status = started ? "Listening… Click the mic again to finish." : "Finish the current recording first."
    }

    func openModels() {
        close()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == Branding.appName })?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .murmurNavigate, object: SidebarDestination.models)
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(name: .murmurNavigate, object: "writing-models")
        }
    }
}

private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

@MainActor
final class WritingAssistantPanel: NSPanel {
    private let acceptsKeyboard: Bool
    init(size: CGSize, keyboard: Bool) {
        acceptsKeyboard = keyboard
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = keyboard
        becomesKeyOnlyIfNeeded = true
    }
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { WritingAssistantController.current?.close() }
}
