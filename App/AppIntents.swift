#if os(iOS)
import AppIntents
import MobileUI

/// Starts a timer from Siri, Shortcuts, a control or the Action button,
/// for what's said or typed as in the command line.
struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Timer"
    static let description = IntentDescription(
        "Starts a timer for what you're working on, written as in the command line, such as “bookings #227 export”. A running timer stops first."
    )

    @Parameter(title: "What", requestValueDialog: "What are you working on?")
    var line: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await TimerActions.start(line)
        return .result(dialog: "\(said)")
    }
}

/// Stops the running timer.
struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop the Timer"
    static let description = IntentDescription("Stops the running timer.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await TimerActions.stop()
        return .result(dialog: "\(said)")
    }
}

/// Opens the app with the command line ready to type in.
struct OpenCommandLineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the Command Line"
    static let description = IntentDescription("Opens Time Tracker with the command line ready to type in.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerActions.openCommandLine()
        return .result()
    }
}

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
