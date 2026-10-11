import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Dedicated native shortcut editor sheet for recording and testing user-configured dictation shortcuts.
struct ShortcutRecorderSheet: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var candidate: ShortcutBinding
    @State private var isRecording = false
    @State private var validationError: String? = nil
    @State private var localEventMonitor: Any? = nil

    // Interactive test area state
    @State private var testMatcher = HotkeyMatcher()
    @State private var isTestPressed = false
    @State private var testEventMonitor: Any? = nil

    init(controller: DictationController) {
        self.controller = controller
        _candidate = State(initialValue: Settings.shared.shortcut)
    }

    private var hasChanges: Bool {
        candidate != settings.shortcut
    }

    private var isValid: Bool {
        validationError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Dictation Shortcut")
                        .font(DS.Font.sectionTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Hold the shortcut to dictate anywhere; release to insert cleaned text.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
            }

            // Current Saved vs Candidate
            HStack(spacing: DS.Space.wide) {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Current Binding")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    ShortcutBadgeView(tokens: settings.shortcut.keycapTokens)
                }

                Divider()
                    .frame(height: 36)
                    .overlay(DS.Color.borderSubtle)

                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text("Candidate")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    ShortcutBadgeView(tokens: candidate.keycapTokens, isHighlighted: true)
                }
                Spacer()
            }
            .padding(DS.Space.base)
            .background(DS.Color.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))

            // Recording Field
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text("Record New Shortcut")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)

                HStack {
                    if isRecording {
                        HStack(spacing: DS.Space.tight) {
                            Circle()
                                .fill(DS.Color.recordRed)
                                .frame(width: 8, height: 8)
                            Text("Press your key combination now… (Esc to cancel)")
                                .font(DS.Font.bodyEmphasis)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
                    } else {
                        Text("Click 'Record' to capture keys, or pick a preset below.")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.textSecondary)
                    }

                    Spacer()

                    if isRecording {
                        MurmurButton("Stop Recording", icon: "stop.fill", style: .secondary) {
                            stopRecording()
                        }
                    } else {
                        MurmurButton("Record Shortcut", icon: "record.circle", style: .primary) {
                            startRecording()
                        }
                    }
                }
                .padding(DS.Space.base)
                .background(isRecording ? DS.Color.accentSoft.opacity(0.3) : DS.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(isRecording ? DS.Color.accent : DS.Color.borderSubtle, lineWidth: isRecording ? 1.5 : 1)
                )

                // Validation feedback
                if let error = validationError {
                    HStack(spacing: DS.Space.tight) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.warningAmber)
                        Text(error)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.warningAmber)
                    }
                    .padding(.horizontal, DS.Space.tight)
                }
            }

            // Quick Modifier-Only Presets
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Text("Modifier-Only Presets")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)

                HStack(spacing: DS.Space.snug) {
                    presetButton("Right Option (Default)", binding: .rightOption)
                    presetButton("Right Command", binding: .rightCommand)
                    presetButton("Fn (Globe)", binding: .fn)
                    presetButton("Right Control", binding: ShortcutBinding(
                        kind: .modifierOnly,
                        specificModifier: .rightControl,
                        keyCode: UInt16(kVK_RightControl)
                    ))
                }
            }

            // Shortcut-only Interactive Test Area
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                HStack {
                    Text("Test Area")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("— does not activate microphone or record audio")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                HStack {
                    HStack(spacing: DS.Space.snug) {
                        Circle()
                            .fill(isTestPressed ? DS.Color.accent : DS.Color.textTertiary)
                            .frame(width: 10, height: 10)
                        Text(isTestPressed ? "Shortcut PRESSED" : "Shortcut RELEASED")
                            .font(DS.Font.counter)
                            .foregroundStyle(isTestPressed ? DS.Color.accent : DS.Color.textSecondary)
                    }
                    Spacer()
                    Text("Hold [\(candidate.displayName)] in this window to test")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .padding(DS.Space.base)
                .background(isTestPressed ? DS.Color.accentSoft : DS.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(isTestPressed ? DS.Color.accent : DS.Color.borderSubtle, lineWidth: 1)
                )
            }

            Divider().overlay(DS.Color.borderSubtle)

            // Footer Actions
            HStack(spacing: DS.Space.base) {
                Button("Reset to Default") {
                    candidate = .defaultBinding
                    validateCandidate()
                    testMatcher.updateBinding(candidate)
                }
                .buttonStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)

                Spacer()

                MurmurButton("Cancel", style: .subtle) {
                    dismissSheet()
                }

                MurmurButton("Save Shortcut", icon: "checkmark", style: .primary) {
                    saveCandidate()
                }
                .disabled(!isValid || !hasChanges)
            }
        }
        .padding(DS.Space.wide)
        .frame(width: 520)
        .background(DS.Color.canvas)
        .onAppear {
            controller.suspendHotkey()
            testMatcher.updateBinding(candidate)
            startTestMonitor()
        }
        .onDisappear {
            stopRecording()
            stopTestMonitor()
            controller.resumeHotkey()
        }
    }

    private func presetButton(_ title: String, binding: ShortcutBinding) -> some View {
        Button {
            candidate = binding
            validateCandidate()
            testMatcher.updateBinding(candidate)
        } label: {
            HStack(spacing: DS.Space.tight) {
                if candidate == binding {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(DS.Font.caption)
            }
            .padding(.horizontal, DS.Space.base)
            .padding(.vertical, DS.Space.snug)
            .background(candidate == binding ? DS.Color.cardSelected : DS.Color.card)
            .foregroundStyle(candidate == binding ? DS.Color.accent : DS.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .strokeBorder(candidate == binding ? DS.Color.accent : DS.Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording Logic

    private func startRecording() {
        isRecording = true
        validationError = nil

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Handle Escape to cancel recording
            if event.keyCode == kVK_Escape {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags
            let mods = ShortcutModifiers(nsFlags: flags)

            if event.type == .flagsChanged {
                // Check if a modifier key alone was tapped
                if let specific = identifySpecificModifier(event: event) {
                    candidate = ShortcutBinding(
                        kind: .modifierOnly,
                        specificModifier: specific,
                        keyCode: UInt16(specific.keyCode)
                    )
                    validateCandidate()
                    testMatcher.updateBinding(candidate)
                }
                return nil
            }

            if event.type == .keyDown {
                // Main key + modifiers combination captured
                candidate = ShortcutBinding(
                    kind: .keyCombination,
                    specificModifier: nil,
                    keyCode: event.keyCode,
                    modifiers: mods
                )
                validateCandidate()
                testMatcher.updateBinding(candidate)
                stopRecording()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        isRecording = false
    }

    private func identifySpecificModifier(event: NSEvent) -> SpecificModifierKey? {
        let keyCode = Int(event.keyCode)
        switch keyCode {
        case kVK_RightOption:  return .rightOption
        case kVK_RightCommand: return .rightCommand
        case kVK_Function:      return .fn
        case kVK_RightControl:  return .rightControl
        case kVK_Option:        return .leftOption
        case kVK_Command:       return .leftCommand
        case kVK_Control:       return .leftControl
        case kVK_RightShift:    return .rightShift
        case kVK_Shift:         return .leftShift
        default:                return nil
        }
    }

    private func validateCandidate() {
        switch candidate.validate() {
        case .success:
            validationError = nil
        case .failure(let error):
            validationError = error.localizedDescription
        }
    }

    // MARK: - Test Area Logic

    private func startTestMonitor() {
        testEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            guard !isRecording else { return event }

            let keyCode = Int64(event.keyCode)
            let flags = event.cgEvent?.flags ?? CGEventFlags()
            let isAutorepeat = event.isARepeat

            let outcome: (action: HotkeyAction, consume: Bool)

            switch event.type {
            case .flagsChanged:
                outcome = testMatcher.handleFlagsChanged(keyCode: keyCode, flags: flags)
            case .keyDown:
                outcome = testMatcher.handleKeyDown(keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat)
            case .keyUp:
                outcome = testMatcher.handleKeyUp(keyCode: keyCode, flags: flags)
            default:
                return event
            }

            if outcome.action == .start {
                isTestPressed = true
            } else if outcome.action == .stop {
                isTestPressed = false
            }

            return outcome.consume ? nil : event
        }
    }

    private func stopTestMonitor() {
        if let monitor = testEventMonitor {
            NSEvent.removeMonitor(monitor)
            testEventMonitor = nil
        }
        isTestPressed = false
        testMatcher.reset()
    }

    // MARK: - Save & Dismiss

    private func saveCandidate() {
        guard isValid else { return }
        settings.shortcut = candidate
        controller.reloadHotkey()
        dismissSheet()
    }

    private func dismissSheet() {
        stopRecording()
        stopTestMonitor()
        dismiss()
    }
}

/// Visual representation of keycap badges.
struct ShortcutBadgeView: View {
    let tokens: [String]
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tokens.indices, id: \.self) { idx in
                Text(tokens[idx])
                    .font(DS.Font.counter)
                    .foregroundStyle(isHighlighted ? DS.Color.accent : DS.Color.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isHighlighted ? DS.Color.accent.opacity(0.5) : DS.Color.borderSubtle, lineWidth: 1)
                    )
            }
        }
    }
}
