import Foundation

/// An entry drawn on a day's timeline.
public struct DayBlock: Identifiable, Hashable, Sendable {
    public var entry: ResolvedEntry
    /// Seconds after midnight, in the entry's own time zone.
    public var startSecond: Int
    /// Seconds after midnight, at most 86 400. An entry that runs past
    /// midnight is cut off at the end of its day.
    public var endSecond: Int
    /// Which of `columns` side-by-side columns the block sits in. Blocks
    /// share a row of columns when their wall-clock times overlap; overlap
    /// warnings come from `Overlaps`, which uses real time.
    public var column: Int
    public var columns: Int

    public var id: UUID { entry.id }
}

/// Lays out a day's entries for the timeline.
///
/// Entries are drawn at their own wall-clock time, like reports: an entry
/// recorded in Berlin at 09:00 shows at 09:00 wherever the Mac is now.
/// Overlapping blocks sit side by side.
public enum DayLayout {
    public static func blocks(on day: LocalDate, entries: [ResolvedEntry], now: Timestamp) -> [DayBlock] {
        var blocks: [DayBlock] = []
        for resolved in entries where resolved.entry.day == day {
            let zone = resolved.entry.timeZone
            let start = resolved.start.local(in: zone)
            let endTime = resolved.end ?? max(now, resolved.start)
            let end = endTime.local(in: zone)
            let startSecond = start.millisecondOfDay / 1000
            let endSecond = end.date == day ? max(startSecond, end.millisecondOfDay / 1000) : 86400
            blocks.append(DayBlock(
                entry: resolved,
                startSecond: startSecond,
                endSecond: endSecond,
                column: 0,
                columns: 1
            ))
        }
        blocks.sort { a, b in
            a.startSecond != b.startSecond ? a.startSecond < b.startSecond : a.id.uuidString < b.id.uuidString
        }

        // Group blocks that overlap one another, then give each block the first
        // column that's free by its start.
        var index = 0
        while index < blocks.count {
            var groupEnd = blocks[index].endSecond
            var last = index
            while last + 1 < blocks.count, blocks[last + 1].startSecond < groupEnd {
                last += 1
                groupEnd = max(groupEnd, blocks[last].endSecond)
            }
            var columnEnds: [Int] = []
            for member in index...last {
                if let free = columnEnds.firstIndex(where: { $0 <= blocks[member].startSecond }) {
                    blocks[member].column = free
                    columnEnds[free] = blocks[member].endSecond
                } else {
                    blocks[member].column = columnEnds.count
                    columnEnds.append(blocks[member].endSecond)
                }
            }
            for member in index...last {
                blocks[member].columns = columnEnds.count
            }
            index = last + 1
        }
        return blocks
    }
}

extension Timestamp {
    /// The instant of a wall-clock time on a date in a time zone, such as
    /// "Europe/Berlin". A time skipped by a daylight-saving change moves
    /// forward, as `Calendar` does.
    public init(date: LocalDate, secondOfDay: Int, zone: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Zones.zone(zone)
        let components = DateComponents(
            year: date.year,
            month: date.month,
            day: date.day,
            hour: secondOfDay / 3600,
            minute: secondOfDay / 60 % 60,
            second: secondOfDay % 60
        )
        self.init(calendar.date(from: components) ?? Date(timeIntervalSince1970: 0))
    }
}
