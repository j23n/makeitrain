#if os(macOS)
import AppKit
import TrackerKit

/// Starts the app model at launch, and saves before quitting.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel { AppModel.shared }
    private var wakeObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshClock()
            }
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasUnsavedChanges else { return .terminateNow }
        Task {
            await model.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
