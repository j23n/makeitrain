import Foundation
import TrackerCore

/// Each project's time this week, this month, in each of the last twelve
/// weeks and in all, as the projects list shows them, worked out in one
/// go. Nil stands for the entries without a project. The running timer
/// counts as far as it has run.
public struct ProjectStats {
    public struct Row: Hashable {
        public var thisWeek: Int64 = 0
        public var thisMonth: Int64 = 0
        /// The last twelve weeks, this week last.
        public var weeks: [Int64] = Array(repeating: 0, count: 12)
        public var total: Int64 = 0
        public var entryCount = 0
        /// The latest entry, for saying what an unassigned one was.
        public var latest: ResolvedEntry?
    }

    public var rows: [UUID?: Row] = [:]

    @MainActor
    public init(model: AppModel) {
        let today = model.today
        let firstWeekday = model.firstWeekday
        let week = ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
        let month = ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)
        let firstWeek = week.lowerBound.adding(days: -7 * 11)
        let now = model.now
        for entry in model.resolved {
            let projectID = entry.entry.projectID
            let duration = entry.duration(now: now)
            let day = entry.entry.day
            var row = rows[projectID] ?? Row()
            row.total += duration
            row.entryCount += 1
            row.latest = entry
            if week.contains(day) {
                row.thisWeek += duration
            }
            if month.contains(day) {
                row.thisMonth += duration
            }
            if day >= firstWeek, day <= week.upperBound {
                let index = (day.daysSince1970 - firstWeek.daysSince1970) / 7
                if (0..<12).contains(index) {
                    row.weeks[index] += duration
                }
            }
            rows[projectID] = row
        }
    }

    public subscript(_ projectID: UUID?) -> Row {
        rows[projectID] ?? Row()
    }

    /// The sum of some projects' rows, for a client's.
    public func sum(_ projectIDs: [UUID]) -> Row {
        var result = Row()
        for id in projectIDs {
            let row = self[id]
            result.thisWeek += row.thisWeek
            result.thisMonth += row.thisMonth
            result.total += row.total
            result.entryCount += row.entryCount
            for index in 0..<12 {
                result.weeks[index] += row.weeks[index]
            }
        }
        return result
    }
}
