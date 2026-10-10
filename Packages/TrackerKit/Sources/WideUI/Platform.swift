import SwiftUI
import TrackerKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The few things the Mac and the iPad do differently in the same screens.

extension View {
    /// A menu drawn as its label alone, as in the Mac's toolbars.
    func plainMenu() -> some View {
        #if os(macOS)
        return menuStyle(.borderlessButton)
        #else
        return self
        #endif
    }

    /// A button drawn as a link.
    func linkButton() -> some View {
        #if os(macOS)
        return buttonStyle(.link)
        #else
        return buttonStyle(.plain).foregroundStyle(Theme.link)
        #endif
    }

    /// A toggle drawn as a checkbox on the Mac, and as a switch elsewhere.
    func checkbox() -> some View {
        #if os(macOS)
        return toggleStyle(.checkbox)
        #else
        return self
        #endif
    }

    /// Runs `action` when Escape is pressed.
    func onEscape(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        return onExitCommand(perform: action)
        #else
        return onKeyPress(.escape) {
            action()
            return .handled
        }
        #endif
    }

    /// Shows the up-and-down cursor over a handle that drags a time, on
    /// the Mac.
    func resizeCursor() -> some View {
        #if os(macOS)
        return onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        #else
        return self
        #endif
    }
}

extension View {
    /// Takes the keys a screen has no use for, so they stop here rather
    /// than at the end of the responder chain, where the Mac plays the
    /// alert sound. The screen's own keys, `keys` and the `letters` in
    /// either case, go on when it can't act on them, so a key that fails
    /// still sounds, as do keys with ⌘ or ⌃, which are shortcuts. Tab and
    /// Shift-Tab, which move between controls, and keys typed in a text
    /// field are left alone.
    @MainActor
    func takesUnusedKeys(_ keys: [KeyEquivalent] = [], letters: String = "") -> some View {
        onKeyPress { press in
            guard !isEditingText(),
                  !press.modifiers.contains(.command),
                  !press.modifiers.contains(.control),
                  press.key != .tab,
                  // Shift-Tab comes as the back-tab character on the Mac.
                  press.characters != "\u{19}",
                  !keys.contains(press.key)
            else { return .ignored }
            let typed = press.characters.lowercased()
            if typed.count == 1, let letter = typed.first, letters.contains(letter) {
                return .ignored
            }
            return .handled
        }
    }
}

/// Takes the keyboard from whatever text field has it, so keys go back to
/// the screen.
@MainActor
func endTextEditing() {
    #if os(macOS)
    NSApp.keyWindow?.makeFirstResponder(nil)
    #else
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

/// Whether a text field has the keyboard, so that keys are text and not
/// the screen's shortcuts: a screen's key handlers run before a field
/// inside it gets the key.
@MainActor
func isEditingText() -> Bool {
    #if os(macOS)
    return NSApp.keyWindow?.firstResponder is NSText
    #else
    foundFirstResponder = nil
    UIApplication.shared.sendAction(#selector(UIResponder.reportAsFirstResponder), to: nil, from: nil, for: nil)
    return foundFirstResponder is UITextField || foundFirstResponder is UITextView
    #endif
}

#if os(iOS)
/// The first responder, as the last search for it found it.
private weak var foundFirstResponder: UIResponder?

extension UIResponder {
    /// Answers a search for the first responder, which UIKit sends to it.
    @objc fileprivate func reportAsFirstResponder() {
        foundFirstResponder = self
    }
}
#endif

/// Where the system lets this app read calendars.
@MainActor
var calendarPrivacySettings: URL? {
    #if os(macOS)
    return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    #else
    return URL(string: UIApplication.openSettingsURLString)
    #endif
}
