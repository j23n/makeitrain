#if os(iOS)
import AppIntents
#if !WIDGET_EXTENSION
import MobileUI
#endif

// The app's intents. They're built into the app and into its widget
// extension, whose Live Activity and controls run them; as Live Activity
// intents they always run in the app, where the data is.

/// Starts a timer from Siri, Shortcuts or the Action button, for what's
/// said or typed as in the command line.
struct StartTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a Timer"
    static let description = IntentDescription(
        "Starts a timer for what you type, as in the command line. A running timer stops first."
    )

    @Parameter(title: "What", requestValueDialog: "What are you working on?")
    var line: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "Open Time Tracker to start a timer.")
        #else
        let said = await TimerActions.start(line)
        return .result(dialog: "\(said)")
        #endif
    }
}

/// Stops the running timer, from Siri, Shortcuts, the Live Activity or
/// Control Center.
struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the Timer"
    static let description = IntentDescription("Stops the running timer.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "Open Time Tracker to stop the timer.")
        #else
        let said = await TimerActions.stop()
        return .result(dialog: "\(said)")
        #endif
    }
}

/// Opens the app with the command line ready to type in.
struct OpenCommandLineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the Command Line"
    static let description = IntentDescription("Opens the command line.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        TimerActions.openCommandLine()
        #endif
        return .result()
    }
}
#endif
