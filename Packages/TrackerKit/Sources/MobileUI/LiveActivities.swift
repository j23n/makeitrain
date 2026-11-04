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
        // The running timer, or the one that just stopped, here or on
        // another device.
        let now = max(model.now, model.environment.now())
        guard let entry = model.liveActivityEntry(at: now, window: Int64(staysAfterStop * 1000)) else { return nil }
        if let end = entry.end {
            return content(for: entry, in: model, end: end.date, ranLong: nil, likelyEnd: nil)
        }
        // It asks once the timer counts as left running, and not before the
        // time it offers to stop at has come.
        let likelyEnd = Corrections.likelyEnd(of: entry, in: model.resolved)
        let ranLong = max(Corrections.ranLongDate(of: entry), likelyEnd ?? .init(milliseconds: 0))
        return content(for: entry, in: model, end: nil, ranLong: ranLong.date, likelyEnd: likelyEnd?.date)
    }

    private static func content(for entry: ResolvedEntry, in model: AppModel, end: Date?, ranLong: Date?, likelyEnd: Date?) -> TimerActivityAttributes.ContentState {
        let project = entry.entry.projectID.flatMap { model.ledger.projects[$0] }
        let detail = entry.entry.note.isEmpty ? entry.entry.tags.joined(separator: " ") : entry.entry.note
        return TimerActivityAttributes.ContentState(
            start: entry.start.date,
            entryID: entry.id,
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

    /// The latest two other entries to switch to.
    private static func shortcuts(in model: AppModel) -> [TimerActivityAttributes.Shortcut] {
        model.switchTargets().map { target in
            let project = target.entry.entry.projectID.flatMap { model.ledger.projects[$0] }
            return TimerActivityAttributes.Shortcut(
                title: project?.name ?? model.ledger.title(of: target.entry.entry),
                color: project?.color ?? "#7F7F7F",
                line: target.line
            )
        }
    }

    /// Starts, updates or ends the Live Activity to show `state`.
    func show(_ state: TimerActivityAttributes.ContentState?) {
        guard let state, ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        // One past its stale date, asking whether the timer still runs, is
        // still the timer's.
        let current = activity ?? Activity<TimerActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
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
        for activity in Activity<TimerActivityAttributes>.activities where activity.activityState == .ended {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
