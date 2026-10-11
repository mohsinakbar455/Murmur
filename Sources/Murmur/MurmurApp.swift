import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // panel, and letting ⌘N spawn a second copy of a tape deck makes no sense.
        Window(Branding.appName, id: "main") {
            MainWindow(controller: delegate.controller)
                .task(id: WritingModelManager.shared.selectedModelURL) {
                    await LearnedTermStore.shared.migrateExamples(PersonalizationStore.shared.examples)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        // Secondary now: status and the hotkey while you're working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: DictationController
    private var writingAssistant: WritingAssistantController?
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?

    override init() {
        MurmurStorage.prepareForLaunch()
        controller = DictationController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A regular app now: dock icon, app menu, standard windows. The HUD is still a
        // non-activating panel, so dictating into another app never steals its focus — that
        // property belongs to the panel, not to the activation policy.
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)
        writingAssistant = WritingAssistantController(dictation: controller)
        writingAssistant?.start()

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        let modelID = Settings.shared.selectedModelID
        Task { try? await SpeechRecognitionService.shared.prepare(modelID: modelID) }

        MeetingPanelController.shared.onOpen = {
            NSApp.windows.first(where: { $0.title == Branding.appName })?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .murmurNavigate, object: SidebarDestination.meetings)
        }
        observeState()
        Log.app.info("Murmur ready — hold \(Settings.shared.shortcut.displayName) to dictate")
    }

    /// `murmur://navigate`, `murmur://snapshot`
    /// as scriptable URL entry points.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == Branding.urlScheme {
            let host = url.host ?? ""
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func queryValue(_ name: String) -> String? {
                queryItems.first(where: { $0.name == name })?.value
            }

            switch host {
            case "navigate":
                if let dest = queryValue("dest") {
                    NotificationCenter.default.post(name: .murmurNavigate, object: dest)
                }
            case "snapshot":
                if let path = queryValue("path") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        Self.captureMainWindow(to: path)
                    }
                }
            case "download":
                if let modelID = queryValue("model") {
                    Task { @MainActor in
                        VoiceModelManager.shared.startDownload(for: modelID)
                    }
                }
            case "transcribe":
                if let filePath = queryValue("file") {
                    let fileURL = URL(fileURLWithPath: filePath)
                    let modelID = queryValue("model") ?? Settings.shared.fileTranscriptionModelID
                    Task { @MainActor in
                        FileTranscriptionService.shared.startTranscription(fileURL: fileURL, modelID: modelID)
                    }
                }
            case "settings":
                NotificationCenter.default.post(name: .murmurNavigate, object: "settings")
                if let search = queryValue("search") {
                    NotificationCenter.default.post(name: Notification.Name("murmurSettingsSearch"), object: search)
                }
                if let expandAdv = queryValue("expand_advanced") {
                    NotificationCenter.default.post(name: Notification.Name("murmurSettingsExpandAdvanced"), object: expandAdv == "true")
                }
                if let scroll = queryValue("scroll") {
                    NotificationCenter.default.post(name: Notification.Name("murmurSettingsScroll"), object: scroll)
                }
            default:
                break
            }
        }
    }

    /// Captures the main Murmur window directly from view hierarchy and saves as PNG.
    @MainActor
    static func captureMainWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.title == Branding.appName && $0.isVisible })
                ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }) else {
            Log.app.error("Snapshot: No visible Murmur window found")
            return
        }
        guard let view = window.contentView else { return }

        let bounds = view.bounds
        let scale = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        // Primary: Render layer hierarchy
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            if let layer = view.layer {
                layer.render(in: context)
            } else {
                view.displayIgnoringOpacity(bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
            }
            if let cgImage = context.makeImage() {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let png = rep.representation(using: .png, properties: [:]) {
                    do {
                        try png.write(to: URL(fileURLWithPath: path))
                        Log.app.info("Snapshot: Saved layer rendering (\(width)x\(height)) to \(path)")
                        return
                    } catch {
                        Log.app.error("Snapshot write failed: \(error)")
                    }
                }
            }
        }

        // Fallback: cacheDisplay
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                Log.app.info("Snapshot: Saved cacheDisplay to \(path)")
                return
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        writingAssistant?.stop()
        controller.deactivate()
        Task { @MainActor in
            await MeetingController.shared.prepareForTermination()
            await WritingModelManager.shared.prepareForTermination()
            await LocalTextRuntime.shared.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        writingAssistant?.stop()
        controller.deactivate()
    }

    /// Shows and hides the HUD in step with the presentation adapter's snapshot visibility.
    private func observeState() {
        withObservationTracking {
            _ = controller.hudAdapter.isVisible
            _ = Settings.shared.showPill
            _ = MeetingController.shared.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.hudAdapter.isVisible && Settings.shared.showPill {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                MeetingPanelController.shared.sync()
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while true {
                if Permissions.hasAccessibility && controller.activate() {
                    Log.app.info("Accessibility granted — hotkey armed")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Loading Parakeet models…" }
        // Reflects what's actually on disk, not just what this menu instance has done.
        return parakeetOnDisk ? "Parakeet models installed ✓" : "Download Parakeet models…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isDownloaded
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        if settings.writingAssistantEnabled {
            Button("Writing Assistant…") { WritingAssistantController.current?.openPastedText() }
        }
        Text("Shortcut: \(settings.shortcut.displayName)")

        Button("Change Shortcut…") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title == Branding.appName }) {
                window.makeKeyAndOrderFront(nil)
            }
        }

        Picker("Engine", selection: Binding(get: { settings.engine }, set: { choice in
            settings.engine = choice
            switch choice {
            case .apple: settings.selectedModelID = "apple-speech"
            case .parakeet:
                if !settings.selectedModelID.hasPrefix("parakeet") { settings.selectedModelID = "parakeet-v3" }
            case .whisper:
                if !settings.selectedModelID.hasPrefix("whisper") { settings.selectedModelID = "whisper-large-v3-turbo" }
            }
        })) {
            ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                Text(choice.displayName).tag(choice)
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
            if settings.writingEngine == .apple, let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Divider()

        // Downloading ~470 MB on the first hold would look like a hang, so offer to do it
        // deliberately instead.
        if settings.engine == .parakeet {
            Button(parakeetStatus) { preloadParakeet() }
                .disabled(isPreloadingParakeet || parakeetOnDisk)
        }

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        Button("Quit Murmur") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension Notification.Name {
    static let murmurNavigate = Notification.Name("murmurNavigate")
}
