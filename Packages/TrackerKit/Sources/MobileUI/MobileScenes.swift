#if os(iOS)
import SwiftUI
import TrackerKit

/// The iPhone and iPad app's scene.
public struct MobileScenes: Scene {
    @State private var model = AppModel(environment: .live())

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Text("Time Tracker")
                .task { await model.start() }
        }
    }
}
#endif
