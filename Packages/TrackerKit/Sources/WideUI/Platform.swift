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

/// What this device is called in sentences, such as "Calendar on this
/// Mac".
@MainActor
var deviceName: String {
    #if os(macOS)
    return "Mac"
    #else
    return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif
}

/// Where the system lets this app read calendars.
@MainActor
var calendarPrivacySettings: URL? {
    #if os(macOS)
    return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    #else
    return URL(string: UIApplication.openSettingsURLString)
    #endif
}
