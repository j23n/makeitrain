#if os(iOS)
import ActivityKit
import Foundation
import TimerActivity
import TrackerCore
import TrackerKit

/// Keeps the Live Activity in step with the running timer: there's one
/// while a timer runs and Settings allows it, showing what it's for,
/// counting up, and offering other entries to switch to. Once the timer
/// stops it stays a few minutes, to continue it, and then goes.
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()

    /// How long a stopped timer's activity stays.
    static let staysAfterStop: TimeInterval = 5 * 60

    private var activity: Activity<TimerActivityAttributes>?

    /// What the Live Activity shows, or nil for none. It's what views
    /// watch, to update the activity when it changes.
    static func state(of model: AppModel) -> TimerActivityAttributes.ContentState? {
        guard model.preferences.showsLiveActivity else { return nil }
        if let running = model.running {
            let ranLong = Corrections.ranLongDate(of: running)
            return content(for: running, in: model, end: nil, ranLong: ranLong.date, likelyEnd: Corrections.likelyEnd(of: running, in: model.resolved, now: ranLong)?.date)
        }
        // The timer that just stopped, here or on another device.
        let now = max(model.now, model.environment.now())
        guard let last = model.resolved.last(where: { $0.end != nil }),
              let end = last.end,
              end <= now,
              end.adding(milliseconds: Int64(staysAfterStop * 1000)) > now
        else { return nil }
        return content(for: last, in: model, end: end.date, ranLong: nil, likelyEnd: nil)
    }

    private static func content(for entry: ResolvedEntry, in model: AppModel, end: Date?, ranLong: Date?, likelyEnd: Date?) -> TimerActivityAttributes.ContentState {
        let project = entry.entry.projectID.flatMap { model.ledger.projects[$0] }
        let detail = entry.entry.note.isEmpty ? entry.entry.tags.joined(separator: " ") : entry.entry.note
        return TimerActivityAttributes.ContentState(
            start: entry.start.date,
            project: project?.name ?? "Unassigned",
            color: project?.color ?? "#7F7F7F",
            detail: detail,
            end: end,
            line: model.startLine(for: entry.entry),
            ranLong: ranLong,
            likelyEnd: likelyEnd,
            switchTo: end == nil ? shortcuts(in: model) : []
        )
    }

    /// The latest two other entries that a line starts again.
    private static func shortcuts(in model: AppModel) -> [TimerActivityAttributes.Shortcut] {
        model.recent(limit: 4).compactMap { entry -> TimerActivityAttributes.Shortcut? in
            guard let line = model.startLine(for: entry.entry) else { return nil }
            let project = entry.entry.projectID.flatMap { model.ledger.projects[$0] }
            return TimerActivityAttributes.Shortcut(
                title: project?.name ?? model.ledger.title(of: entry.entry),
                color: project?.color ?? "#7F7F7F",
                line: line
            )
        }
        .prefix(2)
        .map { $0 }
    }

    /// Starts, updates or ends the Live Activity to show `state`.
    func show(_ state: TimerActivityAttributes.ContentState?) {
        guard let state, ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        let current = activity ?? Activity<TimerActivityAttributes>.activities.first { $0.activityState == .active }
        if let end = state.end {
            // Stopped: the activity that showed the timer says so, with
            // Continue, for a few minutes. None is started for it.
            activity = nil
            guard let current else { return }
            let content = ActivityContent(state: state, staleDate: nil)
            Task {
                await current.end(content, dismissalPolicy: .after(end.addingTimeInterval(Self.staysAfterStop)))
            }
            return
        }
        let content = ActivityContent(state: state, staleDate: state.ranLong)
        if let current {
            activity = current
            Task {
                await current.update(content)
            }
        } else {
            // A stopped timer's activity makes way for the new one.
            dismissEnded()
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

    /// Takes away the activities of timers that stopped.
    private func dismissEnded() {
        for activity in Activity<TimerActivityAttributes>.activities where activity.activityState != .active {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
