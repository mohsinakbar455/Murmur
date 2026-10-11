import AppKit
import Carbon.HIToolbox
import Foundation

/// Backward-compatible wrapper enum for legacy settings and code references.
public enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    public var keyCode: Int64 {
        switch self {
        case .rightOption: return Int64(kVK_RightOption)
        case .fn: return Int64(kVK_Function)
        case .rightCommand: return Int64(kVK_RightCommand)
        }
    }

    public var flag: CGEventFlags {
        switch self {
        case .rightOption: return CGEventFlags(rawValue: 0x40)
        case .rightCommand: return CGEventFlags(rawValue: 0x10)
        case .fn: return .maskSecondaryFn
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .fn: return "fn"
        case .rightCommand: return "Right ⌘"
        }
    }

    public var shouldConsumeEvent: Bool { self != .fn }

    public var asBinding: ShortcutBinding {
        switch self {
        case .rightOption: return .rightOption
        case .fn: return .fn
        case .rightCommand: return .rightCommand
        }
    }
}

/// Watches for a held shortcut (modifier or key combination) using a `CGEventTap`.
///
/// Handles `flagsChanged`, `keyDown`, and `keyUp` globally without needing Murmur to be
/// focused. Requires macOS Accessibility permission.
@MainActor
public final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let matcher = HotkeyMatcher()

    public var isSuspended: Bool = false {
        didSet {
            if isSuspended {
                matcher.reset()
            }
        }
    }

    public var binding: ShortcutBinding = .defaultBinding {
        didSet {
            matcher.updateBinding(binding)
        }
    }

    /// Backward compatibility bridge
    public var key: PushToTalkKey {
        get {
            if binding == .fn { return .fn }
            if binding == .rightCommand { return .rightCommand }
            return .rightOption
        }
        set {
            binding = newValue.asBinding
        }
    }

    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    public init(binding: ShortcutBinding = .defaultBinding) {
        self.binding = binding
        self.matcher.updateBinding(binding)
    }

    public var isActive: Bool {
        tap != nil
    }

    /// - Returns: `false` if the tap couldn't be created — usually missing Accessibility permission.
    @discardableResult
    public func start() -> Bool {
        if tap != nil {
            matcher.updateBinding(binding)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.hotkey.info("[DIAGNOSTIC] tap already active — re-armed for \(self.binding.displayName, privacy: .public)")
            return true
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing? AXIsProcessTrusted=\(Permissions.hasAccessibility)")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("tap created and listening for \(self.binding.displayName, privacy: .public)")
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        matcher.reset()
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isAutorepeat: Bool
    ) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.hotkey.error("event-tap disabled by timeout/user input — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        if isSuspended {
            return false
        }

        let outcome: (action: HotkeyAction, consume: Bool)

        switch type {
        case .flagsChanged:
            outcome = matcher.handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            outcome = matcher.handleKeyDown(keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat)
        case .keyUp:
            outcome = matcher.handleKeyUp(keyCode: keyCode, flags: flags)
        default:
            return false
        }

        switch outcome.action {
        case .start:
            Log.hotkey.info("shortcut triggered (\(self.binding.displayName, privacy: .public))")
            onPress?()
        case .stop:
            Log.hotkey.info("shortcut released (\(self.binding.displayName, privacy: .public))")
            onRelease?()
        case .none:
            break
        }

        return outcome.consume
    }
}
