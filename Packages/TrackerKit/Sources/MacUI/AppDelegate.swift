#if os(macOS)
import AppKit
import TrackerKit

/// Owns the app model, starts it at launch, and saves before quitting.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public lazy var model = AppModel(environment: .live())
    private var wakeObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
        registerShortcut()
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

    /// Registers the shortcut that opens the command line over any app,
    /// as chosen in Settings.
    func registerShortcut() {
        let model = model
        HotKey.shared.register(model.preferences.shortcut) {
            CommandPanel.shared.toggle(model: model)
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
