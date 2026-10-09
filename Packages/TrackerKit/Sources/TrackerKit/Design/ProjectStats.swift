import Foundation
import TrackerCore

/// Each project's time this week, this month, in each of the last twelve
/// weeks and in all, as the projects list shows them. Nil stands for the
/// entries without a project. The running timer counts as far as it has
/// run. Screens take it from `AppModel.projectStats`, which keeps it until
/// the data or the time changes.
public struct ProjectStats {
    public struct Row {
        public var thisWeek: Int64 = 0
        public var thisMonth: Int64 = 0
        /// The last twelve weeks, this week last.
        public var weeks: [Int64] = Array(repeating: 0, count: 12)
        public var total: Int64 = 0
        public var entryCount = 0
        /// The latest entry, for saying what an unassigned one was.
        public var latest: ResolvedEntry?
    }

    private var rows: [UUID?: Row] = [:]

    /// The figures as the model has them now: each day's from its daily
    /// totals, and the time in all from the entries, without working out
    /// their days.
    @MainActor
    init(model: AppModel) {
        let now = model.now
        for entry in model.resolved {
            var row = rows[entry.entry.projectID] ?? Row()
            row.total += entry.duration(now: now)
            row.entryCount += 1
            row.latest = entry
            rows[entry.entry.projectID] = row
        }
        let today = model.today
        let week = ReportPeriod.week.range(containing: today, firstWeekday: model.firstWeekday)
        let month = ReportPeriod.month.range(containing: today, firstWeekday: model.firstWeekday)
        let firstWeek = week.lowerBound.adding(days: -7 * 11)
        for day in (min(firstWeek, month.lowerBound)...max(week.upperBound, month.upperBound)).days {
            for (projectID, time) in model.dayTotals.projects(on: day, now: now) {
                var row = rows[projectID] ?? Row()
                if week.contains(day) {
                    row.thisWeek += time
                }
                if month.contains(day) {
                    row.thisMonth += time
                }
                if day >= firstWeek, day <= week.upperBound {
                    row.weeks[(day.daysSince1970 - firstWeek.daysSince1970) / 7] += time
                }
                rows[projectID] = row
            }
        }
    }

    public subscript(_ projectID: UUID?) -> Row {
        rows[projectID] ?? Row()
    }

    /// Some projects' time this week, this month and in all, added up for
    /// their client's row.
    public func sum(_ projectIDs: [UUID]) -> Row {
        var result = Row()
        for id in projectIDs {
            let row = self[id]
            result.thisWeek += row.thisWeek
            result.thisMonth += row.thisMonth
            result.total += row.total
        }
        return result
    }
}
