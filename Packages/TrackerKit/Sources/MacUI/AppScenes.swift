#if os(macOS)
import AppKit
#if FEEDBACK
import FeedbackKit
#endif
import SwiftUI
import TrackerKit

/// The Mac app's scenes: the menu bar popover, the main window and Settings,
/// all showing the app's one model.
public struct AppScenes: Scene {
    public init() {}

    public var body: some Scene {
        let model = AppModel.shared
        MenuBarExtra {
            MenuBarPopover(model: model)
                #if FEEDBACK
                .feedbackRedaction(Feedback.center)
                #endif
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Time Tracker", id: WindowID.main) {
            MainWindow(model: model)
                .dockIcon()
                #if FEEDBACK
                .feedbackRedaction(Feedback.center)
                #endif
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            FileCommands()
            #if FEEDBACK
            FeedbackCommands(center: Feedback.center)
            #endif
        }

        Settings {
            SettingsView(model: model)
                .dockIcon()
                #if FEEDBACK
                .feedbackRedaction(Feedback.center)
                #endif
        }
    }
}

enum WindowID {
    static let main = "main"
}

/// Shows the Dock icon only while the main window or Settings is open.
@MainActor
final class DockIcon {
    static let shared = DockIcon()
    private var openWindows = 0

    func opened() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func closed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension View {
    /// Counts this window as open for the Dock icon, and brings the app to
    /// the front when it opens, since a menu bar app isn't active by default.
    func dockIcon() -> some View {
        onAppear { DockIcon.shared.opened() }
            .onDisappear { DockIcon.shared.closed() }
    }
}
#endif
