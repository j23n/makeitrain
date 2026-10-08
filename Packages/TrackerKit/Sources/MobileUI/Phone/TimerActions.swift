#if os(iOS)
import Foundation
import TrackerCore
import TrackerKit

/// What the app's App Intents do: start a timer from a line, stop it, or
/// open the command line. An intent can run before the app has a window,
/// so each opens the data first and saves straight after.
@MainActor
public enum TimerActions {
    /// Starts a timer for what a line says, as the command line would,
    /// stopping a running one, and says what happened.
    public static func start(_ line: String) async -> String {
        let model = AppModel.shared
        await model.start()
        let zone = model.environment.timeZone()
        let prompt = "Say a project, tags or a note."
        let reading = model.read(line)
        guard let command = reading.primary else {
            return reading.problem.map { CommandText.message($0, zone: zone) } ?? prompt
        }
        guard let draft = reading.draft else {
            return "That doesn't start a timer. \(prompt)"
        }
        let switching = model.running != nil
        switch model.run(line, undoManager: nil) {
        case .done:
            await model.flush()
            let what = describe(draft, in: model.ledger)
            switch command {
            case .log, .start(_, _, .some):
                return "Logged \(what)."
            default:
                return switching ? "Switched to \(what)." : "Started \(what)."
            }
        case let .problem(problem):
            return CommandText.message(problem, zone: zone)
        case .nothing:
            return prompt
        }
    }

    /// Stops the running timer, and says for how long it ran.
    public static func stop() async -> String {
        let model = AppModel.shared
        await model.start()
        guard let running = model.running else {
            return "No timer is running."
        }
        let what = describe(EntryDraft(running.entry), in: model.ledger)
        model.stopTimer(undoManager: nil)
        let stopped = model.resolved.first { $0.id == running.id } ?? running
        await model.flush()
        return "Stopped \(what) after \(Format.duration(model.duration(of: stopped)))."
    }

    /// Opens the app's command line, empty and ready to type in.
    public static func openCommandLine() {
        AppModel.shared.request = .command("")
    }

    /// Such as "Website, fix login".
    private static func describe(_ draft: EntryDraft, in ledger: Ledger) -> String {
        let project = draft.projectID.flatMap { ledger.projects[$0]?.name }
        switch (project, draft.note.isEmpty) {
        case let (project?, true):
            return project
        case let (project?, false):
            return "\(project), \(draft.note)"
        case (nil, false):
            return draft.note
        case (nil, true):
            return draft.tags.isEmpty ? "a timer" : draft.tags.joined(separator: " ")
        }
    }
}
#endif
