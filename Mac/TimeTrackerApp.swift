import MacUI
import SwiftUI

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        AppScenes(model: delegate.model)
    }
}
