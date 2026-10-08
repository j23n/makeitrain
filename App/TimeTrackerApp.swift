import SwiftUI
#if os(macOS)
import MacUI
#else
import MobileUI
#endif

/// The app on the Mac, iPhone and iPad: the menu bar and main window on the
/// Mac, the tabs on iPhone and the sidebar on iPad, all built in the
/// packages.
@main
struct TimeTrackerApp: App {
    #if os(macOS)
    /// Starts the model at launch and saves before quitting.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    var body: some Scene {
        #if os(macOS)
        AppScenes()
        #else
        MobileScenes()
        #endif
    }
}
