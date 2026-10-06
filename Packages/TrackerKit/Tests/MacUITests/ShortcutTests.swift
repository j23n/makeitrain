#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
import TrackerKit
@testable import MacUI

@MainActor
@Suite struct ShortcutTests {
    func press(_ characters: String, keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    @Test func aShortcutIsWrittenWithItsModifiersInTheMacsOrder() throws {
        let shortcut = try #require(HotKey.shortcut(from: press("t", keyCode: kVK_ANSI_T, [.command, .shift])))
        #expect(shortcut.title == "⇧⌘T")
        #expect(shortcut.keyCode == UInt32(kVK_ANSI_T))
        #expect(shortcut.modifiers == UInt32(cmdKey | shiftKey))

        let space = try #require(HotKey.shortcut(from: press(" ", keyCode: kVK_Space, [.control, .option])))
        #expect(space.title == "⌃⌥Space")
    }

    @Test func aKeyWithoutCommandOptionOrControlIsNoShortcut() {
        #expect(HotKey.shortcut(from: press("t", keyCode: kVK_ANSI_T, [])) == nil)
        #expect(HotKey.shortcut(from: press("T", keyCode: kVK_ANSI_T, [.shift])) == nil)
    }
}
#endif
