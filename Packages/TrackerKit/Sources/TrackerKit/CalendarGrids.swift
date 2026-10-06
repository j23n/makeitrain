import SwiftUI
import TrackerCore

// The arithmetic of the calendars' grids: a month's weeks, and dragging
// blocks on the week's hour grid.

/// The weeks of a month calendar.
public enum MonthGrid {
    /// Every week with a day in the month of `month`, each starting on
    /// `firstWeekday`.
    public static func weeks(of month: LocalDate, firstWeekday: Int) -> [[LocalDate]] {
        let days = ReportPeriod.month.range(containing: month, firstWeekday: firstWeekday)
        var start = days.lowerBound.startOfWeek(firstWeekday: firstWeekday)
        var weeks: [[LocalDate]] = []
        while start <= days.upperBound {
            weeks.append((0..<7).map { start.adding(days: $0) })
            start = start.adding(days: 7)
        }
        return weeks
    }
}

/// The arithmetic of dragging blocks on an hour grid. Times snap to five
/// minutes.
public enum HourGrid {
    /// Five minutes, in seconds.
    public static let snap = 300

    /// What dragging a block changes: where it is, or its start or end.
    public enum DragKind: Hashable, Sendable {
        case move, start, end
    }

    /// A block's start and end after dragging by `delta` seconds, snapped to
    /// five minutes and kept within the day.
    public static func adjusted(_ block: DayBlock, kind: DragKind, by delta: Int) -> (Int, Int) {
        func snapped(_ second: Int) -> Int {
            Int((Double(second) / Double(snap)).rounded()) * snap
        }
        let length = block.endSecond - block.startSecond
        switch kind {
        case .move:
            let start = min(max(snapped(block.startSecond + delta), 0), max(86400 - length, 0))
            return (start, start + length)
        case .start:
            let start = min(max(snapped(block.startSecond + delta), 0), max(block.endSecond - snap, 0))
            return (start, block.endSecond)
        case .end:
            let end = max(min(snapped(block.endSecond + delta), 86400), block.startSecond + snap)
            return (block.startSecond, end)
        }
    }

    /// How many days a block dragged `width` points sideways moves: to the
    /// nearest day's column, within the days shown.
    public static func dayShift(_ width: CGFloat, dayWidth: CGFloat, from index: Int, days: Int) -> Int {
        guard dayWidth > 0 else { return 0 }
        let shift = Int((width / dayWidth).rounded())
        return min(max(shift, -index), days - 1 - index)
    }
}

extension AppModel {
    /// Applies a block dragged on the week's grid. A move puts its entry at
    /// `startSecond` on the day `dayShift` days after `day`, keeping its
    /// length; dragging its start or end changes that to `startSecond` or
    /// `endSecond` on `day`. Times are in the entry's own time zone.
    public func applyDrag(
        _ kind: HourGrid.DragKind,
        to block: DayBlock,
        on day: LocalDate,
        startSecond: Int,
        endSecond: Int,
        dayShift: Int = 0,
        undoManager: UndoManager?
    ) {
        let resolved = block.entry
        let zone = resolved.entry.timeZone
        func time(_ second: Int, on date: LocalDate) -> Timestamp {
            Timestamp(date: date, secondOfDay: second, zone: zone)
        }
        switch kind {
        case .move:
            guard startSecond != block.startSecond || dayShift != 0 else { return }
            let shift = resolved.start.distance(to: time(startSecond, on: day.adding(days: dayShift)))
            updateEntries([block.id], actionName: "Move Entry", undoManager: undoManager) { entry in
                entry.start = entry.start.adding(milliseconds: shift)
                entry.end = entry.end.map { $0.adding(milliseconds: shift) }
            }
        case .start:
            guard startSecond != block.startSecond else { return }
            if resolved.isRunning {
                setRunningStart(time(startSecond, on: day), undoManager: undoManager)
            } else {
                updateEntries([block.id], actionName: "Change Start", undoManager: undoManager) {
                    $0.start = time(startSecond, on: day)
                }
            }
        case .end:
            guard endSecond != block.endSecond else { return }
            updateEntries([block.id], actionName: "Change End", undoManager: undoManager) {
                $0.end = time(endSecond, on: day)
            }
        }
    }
}
