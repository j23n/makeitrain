#if os(iOS)
import ActivityKit
import Foundation
import TimerActivity
import TrackerCore
import TrackerKit

/// Keeps the Live Activity in step with the running timer: there's one
/// while a timer runs and Settings allows it, showing what it's for and
/// counting up, and none otherwise.
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()

    private var activity: Activity<TimerActivityAttributes>?

    /// What the Live Activity shows, or nil for none. It's what views
    /// watch, to update the activity when it changes.
    static func state(of model: AppModel) -> TimerActivityAttributes.ContentState? {
        guard model.preferences.showsLiveActivity, let running = model.running else { return nil }
        let project = running.entry.projectID.flatMap { model.ledger.projects[$0] }
        let detail = running.entry.note.isEmpty ? running.entry.tags.joined(separator: " ") : running.entry.note
        return TimerActivityAttributes.ContentState(
            start: running.start.date,
            project: project?.name ?? "Unassigned",
            color: project?.color ?? "#7F7F7F",
            detail: detail
        )
    }

    /// Starts, updates or ends the Live Activity to show `state`.
    func show(_ state: TimerActivityAttributes.ContentState?) {
        guard let state, ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activity ?? Activity<TimerActivityAttributes>.activities.first {
            activity = current
            Task {
                await current.update(content)
            }
        } else {
            activity = try? Activity.request(attributes: TimerActivityAttributes(), content: content)
        }
    }

    private func end() {
        activity = nil
        for activity in Activity<TimerActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
