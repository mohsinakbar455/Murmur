import Testing
import Foundation
import Carbon.HIToolbox
@testable import Murmur

@Suite("Shortcut Tests")
struct ShortcutTests {

    @Test("Press to Toggle starts on the first press and stops on the next")
    func toggleRecordingActions() {
        #expect(DictationShortcutAction.resolve(.start, mode: .toggle, state: .idle) == .start)
        #expect(DictationShortcutAction.resolve(.stop, mode: .toggle, state: .starting) == .none)
        #expect(DictationShortcutAction.resolve(.stop, mode: .toggle, state: .listening) == .none)
        #expect(DictationShortcutAction.resolve(.start, mode: .toggle, state: .listening) == .stop)
        #expect(DictationShortcutAction.resolve(.start, mode: .toggle, state: .finishing) == .none)
    }

    @Test("Hold to Talk stops when released")
    func holdRecordingActions() {
        #expect(DictationShortcutAction.resolve(.start, mode: .holdToTalk, state: .idle) == .start)
        #expect(DictationShortcutAction.resolve(.stop, mode: .holdToTalk, state: .listening) == .stop)
        #expect(DictationShortcutAction.resolve(.start, mode: .holdToTalk, state: .listening) == .none)
    }

    @Test("Legacy push-to-talk preference migration")
    func legacyMigration() {
        let rightOptionMigrated = ShortcutBinding.migrate(from: "rightOption")
        #expect(rightOptionMigrated.kind == .modifierOnly)
        #expect(rightOptionMigrated.specificModifier == .rightOption)

        let fnMigrated = ShortcutBinding.migrate(from: "fn")
        #expect(fnMigrated.kind == .modifierOnly)
        #expect(fnMigrated.specificModifier == .fn)

        let rightCmdMigrated = ShortcutBinding.migrate(from: "rightCommand")
        #expect(rightCmdMigrated.kind == .modifierOnly)
        #expect(rightCmdMigrated.specificModifier == .rightCommand)

        let nilMigrated = ShortcutBinding.migrate(from: nil)
        #expect(nilMigrated == .defaultBinding)

        let unknownMigrated = ShortcutBinding.migrate(from: "someRandomKey")
        #expect(unknownMigrated == .defaultBinding)
    }

    @Test("ShortcutBinding serialization round-trip")
    func serializationRoundTrip() throws {
        let customBinding = ShortcutBinding(
            kind: .keyCombination,
            specificModifier: nil,
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.control, .option]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(customBinding)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShortcutBinding.self, from: data)

        #expect(decoded == customBinding)
        #expect(decoded.displayName == "⌃⌥M")
    }

    @Test("Shortcut validation rejects bare typing keys and accepts combinations")
    func validationRules() {
        // Bare typing key 'A'
        let bareA = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: []
        )
        if case .failure(let err) = bareA.validate() {
            #expect(err == .bareTypingKey("A"))
        } else {
            Issue.record("Bare typing key should have failed validation")
        }

        // Shift-only 'A'
        let shiftA = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: [.shift]
        )
        if case .failure(let err) = shiftA.validate() {
            #expect(err == .shiftOnly("A"))
        } else {
            Issue.record("Shift-only key should have failed validation")
        }

        // Escape forbidden
        let escapeBinding = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_Escape),
            modifiers: [.command]
        )
        if case .failure(let err) = escapeBinding.validate() {
            #expect(err == .escapeForbidden)
        } else {
            Issue.record("Escape should be forbidden")
        }

        // Valid Control+Option+M
        let validCombo = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.control, .option]
        )
        if case .failure(let err) = validCombo.validate() {
            Issue.record("Expected valid combo to pass validation, got \(err)")
        }

        // Valid modifier-only preset
        let validPreset = ShortcutBinding.rightOption
        if case .failure(let err) = validPreset.validate() {
            Issue.record("Expected valid preset to pass validation, got \(err)")
        }
    }

    @Test("HotkeyMatcher modifier-only activation and release")
    func modifierOnlyMatching() {
        let matcher = HotkeyMatcher(binding: .rightOption)
        let rightOptionCode = SpecificModifierKey.rightOption.keyCode
        let rightOptionFlag = SpecificModifierKey.rightOption.flag

        // Initial state
        #expect(!matcher.isPressed)

        // Press Right Option
        let pressResult = matcher.handleFlagsChanged(
            keyCode: rightOptionCode,
            flags: rightOptionFlag
        )
        #expect(pressResult.action == .start)
        #expect(pressResult.consume == true)
        #expect(matcher.isPressed)

        // Release Right Option
        let releaseResult = matcher.handleFlagsChanged(
            keyCode: rightOptionCode,
            flags: []
        )
        #expect(releaseResult.action == .stop)
        #expect(releaseResult.consume == true)
        #expect(!matcher.isPressed)
    }

    @Test("HotkeyMatcher left vs right modifier discrimination")
    func leftRightDiscrimination() {
        let matcher = HotkeyMatcher(binding: .rightOption)

        // Press Left Option (code 58, NX_DEVICELALTKEYMASK)
        let leftOptionCode = SpecificModifierKey.leftOption.keyCode
        let leftOptionFlag = SpecificModifierKey.leftOption.flag

        let pressLeft = matcher.handleFlagsChanged(
            keyCode: leftOptionCode,
            flags: leftOptionFlag
        )
        // Should NOT trigger start because binding is Right Option!
        #expect(pressLeft.action == .none)
        #expect(!matcher.isPressed)
    }

    @Test("HotkeyMatcher key combination: main-key-first release order")
    func combinationMainKeyFirstRelease() {
        let binding = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.control, .option]
        )
        let matcher = HotkeyMatcher(binding: binding)

        let flags: CGEventFlags = [.maskControl, .maskAlternate]

        // 1. KeyDown with required modifiers
        let keyDown = matcher.handleKeyDown(
            keyCode: Int64(kVK_ANSI_M),
            flags: flags,
            isAutorepeat: false
        )
        #expect(keyDown.action == .start)
        #expect(keyDown.consume == true)
        #expect(matcher.isPressed)

        // 2. Autorepeat while held should not re-trigger start
        let autorepeat = matcher.handleKeyDown(
            keyCode: Int64(kVK_ANSI_M),
            flags: flags,
            isAutorepeat: true
        )
        #expect(autorepeat.action == .none)
        #expect(autorepeat.consume == true) // consumed so repeat characters aren't typed
        #expect(matcher.isPressed)

        // 3. Release main key 'M' while modifiers are still held
        let keyUp = matcher.handleKeyUp(
            keyCode: Int64(kVK_ANSI_M),
            flags: flags
        )
        #expect(keyUp.action == .stop)
        #expect(keyUp.consume == true)
        #expect(!matcher.isPressed)
    }

    @Test("HotkeyMatcher key combination: modifier-first release order")
    func combinationModifierFirstRelease() {
        let binding = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.control, .option]
        )
        let matcher = HotkeyMatcher(binding: binding)

        let initialFlags: CGEventFlags = [.maskControl, .maskAlternate]

        // 1. KeyDown with required modifiers
        let keyDown = matcher.handleKeyDown(
            keyCode: Int64(kVK_ANSI_M),
            flags: initialFlags,
            isAutorepeat: false
        )
        #expect(keyDown.action == .start)
        #expect(matcher.isPressed)

        // 2. User releases Option key before releasing 'M'
        let flagsAfterOptionRelease: CGEventFlags = [.maskControl]
        let flagChange = matcher.handleFlagsChanged(
            keyCode: SpecificModifierKey.leftOption.keyCode,
            flags: flagsAfterOptionRelease
        )
        #expect(flagChange.action == .stop)
        #expect(!matcher.isPressed)

        // 3. Trailing keyUp of 'M' afterwards should still be safely consumed
        let trailingKeyUp = matcher.handleKeyUp(
            keyCode: Int64(kVK_ANSI_M),
            flags: flagsAfterOptionRelease
        )
        #expect(trailingKeyUp.action == .none)
        #expect(trailingKeyUp.consume == true)
    }

    @Test("HotkeyMatcher wrong modifiers do not trigger")
    func wrongModifiersDoNotTrigger() {
        let binding = ShortcutBinding(
            kind: .keyCombination,
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.control, .option]
        )
        let matcher = HotkeyMatcher(binding: binding)

        // Only Control, missing Option
        let wrongFlags: CGEventFlags = [.maskControl]
        let result = matcher.handleKeyDown(
            keyCode: Int64(kVK_ANSI_M),
            flags: wrongFlags,
            isAutorepeat: false
        )
        #expect(result.action == .none)
        #expect(!result.consume)
        #expect(!matcher.isPressed)
    }
}
