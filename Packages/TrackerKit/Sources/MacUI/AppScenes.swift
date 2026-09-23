#if os(macOS)
import SwiftUI
import TrackerKit

/// The Mac app's scenes: the menu bar popover, the main window and Settings.
public struct AppScenes: Scene {
    @State private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            Text("Time Tracker")
                .padding()
        } label: {
            Image(systemName: "stopwatch")
        }
        .menuBarExtraStyle(.window)

        Window("Time Tracker", id: "main") {
            Text("Entries")
                .frame(minWidth: 480, minHeight: 320)
        }

        Settings {
            Text("Settings")
                .padding()
        }
    }
}
#endif
