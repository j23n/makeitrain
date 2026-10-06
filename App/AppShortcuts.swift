#if os(iOS)
import AppIntents

/// The intents as App Shortcuts, so Siri and Spotlight offer them without
/// setting anything up.
struct TimeTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Start tracking time in \(.applicationName)",
            ],
            shortTitle: "Start a Timer",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopTimerIntent(),
            phrases: [
                "Stop the timer in \(.applicationName)",
                "Stop tracking time in \(.applicationName)",
            ],
            shortTitle: "Stop the Timer",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: OpenCommandLineIntent(),
            phrases: [
                "Open the command line in \(.applicationName)",
            ],
            shortTitle: "Command Line",
            systemImageName: "chevron.right"
        )
    }
}
#endif
