import SwiftUI
import TrackerKit

/// What the View menu does in the focused wide window: showing another
/// zoom, and going back and forward.
struct WideNavigation {
    let canGoBack: Bool
    let canGoForward: Bool
    /// Shows a zoom around the day shown, as the bar's zoom does.
    let show: (Zoom) -> Void
    let goBack: () -> Void
    let goForward: () -> Void
}

struct WideNavigationKey: FocusedValueKey {
    typealias Value = WideNavigation
}

extension FocusedValues {
    /// The View menu's screens, Back and Forward, in the focused wide window.
    var wideNavigation: WideNavigation? {
        get { self[WideNavigationKey.self] }
        set { self[WideNavigationKey.self] = newValue }
    }
}

/// The View menu's screens, Week, Month, Year and Projects with ⌘1 to ⌘4,
/// and Back (⌘[) and Forward (⌘]), for the focused wide window: the
/// Mac's main window, or an iPad's wide window with a keyboard.
public struct ViewCommands: Commands {
    @FocusedValue(\.wideNavigation) private var navigation

    public init() {}

    public var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(Zoom.allCases, id: \.self) { zoom in
                Button(zoom.title) {
                    navigation?.show(zoom)
                }
                .keyboardShortcut(KeyEquivalent(zoom.shortcutKey))
                .disabled(navigation == nil)
            }
            Divider()
            Button("Back") {
                navigation?.goBack()
            }
            .keyboardShortcut("[")
            .disabled(navigation?.canGoBack != true)
            Button("Forward") {
                navigation?.goForward()
            }
            .keyboardShortcut("]")
            .disabled(navigation?.canGoForward != true)
            Divider()
        }
    }
}
