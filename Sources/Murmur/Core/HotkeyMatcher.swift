import AppKit
import Foundation

/// Action triggered by the hotkey state machine.
public enum HotkeyAction: Equatable, Sendable {
    case none
    case start
    case stop
}

/// Pure, deterministic state machine for push-to-talk shortcut detection.
/// Supports both modifier-only keys and modifier + main key combinations.
public final class HotkeyMatcher: @unchecked Sendable {
    public private(set) var binding: ShortcutBinding

    private final class StateBox {
        var isPressed: Bool = false
        var activeKeyCode: UInt16 = 0
        var activeModifiers: ShortcutModifiers = []
        var consumedKeyDownKeyCode: UInt16? = nil
    }

    private let state = StateBox()

    public init(binding: ShortcutBinding = .defaultBinding) {
        self.binding = binding
    }

    public func updateBinding(_ newBinding: ShortcutBinding) {
        reset()
        self.binding = newBinding
    }

    public var isPressed: Bool {
        state.isPressed
    }

    public func reset() {
        state.isPressed = false
        state.activeKeyCode = 0
        state.activeModifiers = []
        state.consumedKeyDownKeyCode = nil
    }

    // MARK: - Event Handlers

    /// Handles CGEventType.flagsChanged.
    public func handleFlagsChanged(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> (action: HotkeyAction, consume: Bool) {
        switch binding.kind {
        case .modifierOnly:
            guard let specific = binding.specificModifier,
                  keyCode == specific.keyCode else {
                return (.none, false)
            }

            let nowPressed = flags.contains(specific.flag)
            guard nowPressed != state.isPressed else {
                return (.none, false)
            }

            state.isPressed = nowPressed
            let action: HotkeyAction = nowPressed ? .start : .stop
            return (action, specific.shouldConsumeEvent)

        case .keyCombination:
            // When a key combination is active, releasing any required modifier stops the gesture
            // (modifier-first release order).
            if state.isPressed {
                let currentModifiers = ShortcutModifiers(cgFlags: flags)
                if !binding.modifiers.isSubset(of: currentModifiers) {
                    state.isPressed = false
                    state.activeKeyCode = 0
                    state.activeModifiers = []
                    return (.stop, false)
                }
            }
            return (.none, false)
        }
    }

    /// Handles CGEventType.keyDown.
    public func handleKeyDown(
        keyCode: Int64,
        flags: CGEventFlags,
        isAutorepeat: Bool
    ) -> (action: HotkeyAction, consume: Bool) {
        guard binding.kind == .keyCombination else {
            return (.none, false)
        }

        guard keyCode == Int64(binding.keyCode) else {
            return (.none, false)
        }

        // Ignore autorepeat events so we don't start/stop repeatedly while held.
        if isAutorepeat {
            if state.isPressed {
                return (.none, true)
            }
            return (.none, false)
        }

        // Verify that required modifiers are held.
        let currentModifiers = ShortcutModifiers(cgFlags: flags)
        guard binding.modifiers.isSubset(of: currentModifiers) else {
            return (.none, false)
        }

        if !state.isPressed {
            state.isPressed = true
            state.activeKeyCode = binding.keyCode
            state.activeModifiers = binding.modifiers
            state.consumedKeyDownKeyCode = binding.keyCode
            return (.start, true)
        }

        return (.none, true)
    }

    /// Handles CGEventType.keyUp.
    public func handleKeyUp(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> (action: HotkeyAction, consume: Bool) {
        guard binding.kind == .keyCombination else {
            return (.none, false)
        }

        let isTargetKey = (keyCode == Int64(binding.keyCode))
        let wasConsumedDown = (state.consumedKeyDownKeyCode == UInt16(keyCode))

        if state.isPressed && isTargetKey {
            // Main key was released (main-key-first release order).
            state.isPressed = false
            state.activeKeyCode = 0
            state.activeModifiers = []
            state.consumedKeyDownKeyCode = nil
            return (.stop, true)
        }

        if wasConsumedDown {
            state.consumedKeyDownKeyCode = nil
            return (.none, true)
        }

        return (.none, false)
    }
}
