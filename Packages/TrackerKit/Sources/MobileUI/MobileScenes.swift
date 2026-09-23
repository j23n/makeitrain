#if os(iOS)
import SwiftUI
import TrackerKit

/// The iPhone and iPad app's scene.
public struct MobileScenes: Scene {
    @State private var model = AppModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Text("Time Tracker")
        }
    }
}
#endif
