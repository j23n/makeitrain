import SwiftUI

/// A column of the projects table. Each has a least width; the name,
/// repositories and calendar share the room left over. A table too narrow
/// for all of them leaves some out, in `hidingOrder`, so that it never
/// runs past the window's edges.
enum ProjectColumn: CaseIterable, Hashable {
    case name, repositories, calendar, contract, week, month, spark, total

    /// The room between two columns.
    static let spacing: CGFloat = 16
    /// The room before the first column and after the last.
    static let padding: CGFloat = 16

    /// The columns a narrowing table leaves out, first to last: the last
    /// twelve weeks, the calendar, the repositories, the total and the
    /// contract. The name and the time this week and this month always show.
    static let hidingOrder: [ProjectColumn] = [.spark, .calendar, .repositories, .total, .contract]

    /// The least width of the column's content.
    var minimumWidth: CGFloat {
        switch self {
        case .name: 220
        case .repositories: 150
        case .calendar: 170
        case .contract: 230
        case .week: 84
        case .month: 100
        case .spark: 156
        case .total: 104
        }
    }

    /// Whether the column takes a share of the room the others leave.
    var isFlexible: Bool {
        self == .name || self == .repositories || self == .calendar
    }

    /// The least width of a table with these columns.
    static func minimumWidth(of columns: Set<ProjectColumn>) -> CGFloat {
        let content = columns.reduce(0) { $0 + $1.minimumWidth }
        return content + spacing * CGFloat(max(columns.count - 1, 0)) + padding * 2
    }

    /// The columns that fit a table this wide: all of them, less those
    /// `hidingOrder` leaves out first until the rest fit.
    static func fitting(_ width: CGFloat) -> Set<ProjectColumn> {
        var columns = Set(allCases)
        for column in hidingOrder where minimumWidth(of: columns) > width {
            columns.remove(column)
        }
        return columns
    }
}

private struct ProjectColumnsKey: EnvironmentKey {
    static let defaultValue = Set(ProjectColumn.allCases)
}

extension EnvironmentValues {
    /// The projects table's columns that fit its width, which each of its
    /// rows shows.
    var projectColumns: Set<ProjectColumn> {
        get { self[ProjectColumnsKey.self] }
        set { self[ProjectColumnsKey.self] = newValue }
    }
}
