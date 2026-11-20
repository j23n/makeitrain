import CoreGraphics

/// A column of the projects table, with its least width. The name,
/// repositories and calendar share the room the others leave. A table
/// narrower than all of them together scrolls sideways.
enum ProjectColumn: CaseIterable, Hashable {
    case name, repositories, calendar, contract, week, month, spark, total

    /// The room between two columns.
    static let spacing: CGFloat = 16
    /// The room before the first column and after the last.
    static let padding: CGFloat = 16

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

    /// The least width of the table: its columns, the room between them
    /// and its padding.
    static let tableWidth: CGFloat = {
        let content = allCases.reduce(0) { $0 + $1.minimumWidth }
        return content + spacing * CGFloat(allCases.count - 1) + padding * 2
    }()

    /// The width to lay the table out at in a view this wide: the view's
    /// width, or the table's least width when the view is narrower, which
    /// then scrolls sideways.
    static func layoutWidth(in width: CGFloat) -> CGFloat {
        max(width, tableWidth)
    }
}
