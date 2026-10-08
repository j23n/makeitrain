import Foundation

// The figures over a report's details: how many days had time logged, the
// average of those days, and how the total compares with the period before.

extension Report {
    /// The time logged on an average day with time logged, or 0 when no
    /// day has any. Days off don't pull it down.
    public var averagePerDayWorked: Int64 {
        let worked = daysWorked
        return worked == 0 ? 0 : total / Int64(worked)
    }
}

/// A report's total next to the period before it, with the same filters:
/// the day, week or month before, or as many days before a custom range.
///
/// While the period is under way, its days so far are held against as many
/// days at the start of the period before, so a week on its Wednesday is
/// compared with Monday to Wednesday of the week before rather than with
/// all of it.
public struct ReportComparison: Hashable, Sendable {
    /// The days compared with.
    public var previousRange: ClosedRange<LocalDate>
    /// The time logged on them.
    public var previousTotal: Int64
    /// The time logged in the report's period, or on its days so far.
    public var total: Int64

    /// The change in percent of the time logged before, rounded, or nil
    /// when nothing was logged before, which no percentage describes.
    public var percent: Int? {
        guard previousTotal > 0 else { return nil }
        return Int((Double(total - previousTotal) / Double(previousTotal) * 100).rounded())
    }

    /// Compares `report`, which covers a `period`, with the period before
    /// it. `today` decides whether the period is under way.
    public init(
        _ report: Report,
        period: ReportPeriod,
        today: LocalDate,
        ledger: Ledger,
        resolved: [ResolvedEntry]
    ) {
        let range = report.request.range
        var previous = period.shift(range, by: -1)
        if range.contains(today), today < range.upperBound {
            let elapsed = today.daysSince1970 - range.lowerBound.daysSince1970
            previous = previous.lowerBound...min(previous.lowerBound.adding(days: elapsed), previous.upperBound)
            total = report.entries.reduce(0) { $1.entry.day <= today ? $0 + $1.length : $0 }
        } else {
            total = report.total
        }
        previousRange = previous

        // The entries a report of those days would have: stopped ones that
        // pass the same filters.
        var request = report.request
        request.range = previous
        let matches = request.filter.matcher(in: ledger)
        previousTotal = resolved.reduce(0) { sum, entry in
            !entry.isRunning && matches(entry) ? sum + entry.length : sum
        }
    }
}
