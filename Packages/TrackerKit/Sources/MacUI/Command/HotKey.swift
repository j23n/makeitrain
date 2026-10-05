#if os(macOS)
import AppKit
import Carbon.HIToolbox
import TrackerKit

/// A shortcut that works over any app, through Carbon's hot keys, which
/// don't need the accessibility permission a key monitor would.
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: () -> Void = {}

    /// Registers `shortcut`, replacing the one before, or removes it for nil.
    func register(_ shortcut: Preferences.Shortcut?, action: @escaping () -> Void) {
        unregister()
        guard let shortcut else { return }
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    HotKey.shared.action()
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x5454_524B), id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// The shortcut a key press makes, or nil for a key that needs a
    /// modifier and has none, so a plain letter can't be taken over.
    static func shortcut(from event: NSEvent) -> Preferences.Shortcut? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.subtracting(.shift).isEmpty else { return nil }
        var modifiers: UInt32 = 0
        var title = ""
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
            title += "⌃"
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
            title += "⌥"
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
            title += "⇧"
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
            title += "⌘"
        }
        title += keyName(event)
        return Preferences.Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, title: title)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
#endif
