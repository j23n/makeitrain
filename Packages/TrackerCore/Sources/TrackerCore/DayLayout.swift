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

    /// The hours a day's grid runs over: the whole day, so an entry can be
    /// drawn at any hour.
    public static let allDay = 0..<24

    /// The hour a day's grid opens at, at its top: the first of `shown`,
    /// or on today, once that's late, nine hours before the hour now, so
    /// the time now is in view.
    public static func openingHour(shown: Range<Int>, nowHour: Int?) -> Int {
        guard let nowHour else { return shown.lowerBound }
        return max(shown.lowerBound, nowHour - 9)
    }

    /// The hours a day's grid shows at first, before it's scrolled: 7:00
    /// to 19:00, widened to its blocks, to the entries suggestions would
    /// add, and to the hour it is now, when that's given.
    public static func hours(blocks: some Sequence<DayBlock>, additions: some Sequence<TimeEntry>, nowHour: Int?) -> Range<Int> {
        var first = 7
        var last = 19
        for block in blocks {
            first = min(first, block.startSecond / 3600)
            last = max(last, Int((Double(block.endSecond) / 3600).rounded(.up)))
        }
        for entry in additions {
            let zone = entry.timeZone
            first = min(first, entry.start.local(in: zone).hour)
            if let end = entry.end {
                last = max(last, end.local(in: zone).hour + 1)
            }
        }
        if let nowHour {
            first = min(first, nowHour)
            last = max(last, nowHour + 1)
        }
        return max(0, first)..<min(24, max(last, first + 1))
    }

    /// The least height a block is drawn at on a grid, in points, so an
    /// entry of a minute or two still shows.
    public static let hairline = 3.0

    /// How tall a block from `startSecond` to `endSecond` is on a grid
    /// `hourHeight` points to the hour: as tall as its entry is long, so it
    /// ends where its entry does at any length, and the entry that starts
    /// then starts right below it. Shorter than a hairline, it's a hairline,
    /// but only as far as `nextStart`, where the next block starts, so it
    /// never covers it.
    public static func height(from startSecond: Int, to endSecond: Int, hourHeight: Double, nextStart: Int? = nil) -> Double {
        let length = Double(max(endSecond - startSecond, 0)) / 3600 * hourHeight
        guard length < hairline else { return length }
        let room = nextStart.map { Double(max($0 - startSecond, 0)) / 3600 * hourHeight } ?? hairline
        return max(length, min(hairline, room))
    }

    /// Where a block drawn from `top`, `height` points tall, can be clicked
    /// or tapped: the block itself, or for one shorter than `minimum`,
    /// `minimum` points centered on it. That reaches over the edges of the
    /// blocks before and after it, so the short block goes over them, and
    /// it can be picked even in a run of entries back to back.
    public static func hitSpan(top: Double, height: Double, minimum: Double) -> (top: Double, height: Double) {
        guard height < minimum else { return (top, height) }
        return (top - (minimum - height) / 2, minimum)
    }

    /// Where the first of `blocks` that starts once `block` has ended
    /// starts, which a short block mustn't reach.
    public static func nextStart(after block: DayBlock, in blocks: [DayBlock]) -> Int? {
        blocks.lazy
            .filter { $0.id != block.id && $0.startSecond >= block.endSecond }
            .map(\.startSecond)
            .min()
    }

    /// Where a time falls on a day's grid, in seconds after midnight in
    /// `zone`: 0 for a time before the day, and 86 400 for one after it.
    public static func second(of time: Timestamp, on day: LocalDate, zone: String) -> Int {
        let local = time.local(in: zone)
        if local.date == day {
            return local.millisecondOfDay / 1000
        }
        return local.date < day ? 0 : 86400
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

/// Where a new entry drawn on a day's grid goes, in seconds after midnight:
/// from dragging across empty space, from touching and holding it, or from
/// double-clicking it. Times snap to five minutes, as dragging an entry
/// does, a new entry is at least five minutes long, and it ends by
/// `latest`: now on today, so it can't end in the future, or else 23:55,
/// so its end is a time of the same day.
public enum NewEntrySpan {
    /// Five minutes, in seconds.
    public static let snap = 300
    /// How long a new entry made by touching and holding is, before it's
    /// dragged: 30 minutes.
    public static let heldLength = 1800
    /// How long a new entry made by double-clicking is: an hour.
    public static let clickedLength = 3600
    /// The latest a new entry can end on a day: 23:55.
    public static let lastEnd = 86400 - snap

    /// The latest end on `day`: now on today, the day's last end on a day
    /// before it, and nothing after it.
    public static func latest(on day: LocalDate, now: Timestamp, zone: String) -> Int {
        let local = now.local(in: zone)
        if day < local.date { return lastEnd }
        if day > local.date { return 0 }
        return min(local.millisecondOfDay / 1000 / snap * snap, lastEnd)
    }

    /// Dragged from `from` to `to`, either way: the times between them,
    /// snapped. Nil when there's no room for one, as just after midnight.
    public static func dragged(from: Int, to: Int, latest: Int) -> (start: Int, end: Int)? {
        let limit = min(latest, lastEnd)
        guard limit >= snap else { return nil }
        var start = min(max(rounded(min(from, to)), 0), limit)
        var end = min(max(rounded(max(from, to)), 0), limit)
        if end - start < snap {
            end = min(start + snap, limit)
            start = end - snap
        }
        return (start, end)
    }

    /// Touched and held at `at`, then dragged to `to`: half an hour from
    /// the five minutes under the finger, until the drag takes it further
    /// down, or above where it started.
    public static func held(at: Int, to: Int, latest: Int) -> (start: Int, end: Int)? {
        if to < at - snap / 2 || to - at > heldLength {
            return dragged(from: at / snap * snap, to: to, latest: latest)
        }
        return placed(at: at, length: heldLength, latest: latest)
    }

    /// Double-clicked at `at`: an hour from the five minutes under the
    /// pointer.
    public static func clicked(at: Int, latest: Int) -> (start: Int, end: Int)? {
        placed(at: at, length: clickedLength, latest: latest)
    }

    /// `length` from the five minutes before `at`, moved earlier when it
    /// would end after `latest`.
    static func placed(at: Int, length: Int, latest: Int) -> (start: Int, end: Int)? {
        let limit = min(latest, lastEnd)
        guard limit >= snap else { return nil }
        let end = min(max(at / snap * snap, 0) + length, limit)
        return (max(end - length, 0), end)
    }

    /// A new entry's start or end dragged to `second`: the other end stays,
    /// and it stays at least five minutes long.
    public static func adjusted(start: Int, end: Int, movingStart: Bool, to second: Int, latest: Int) -> (start: Int, end: Int) {
        let limit = min(latest, lastEnd)
        if movingStart {
            return (min(max(rounded(second), 0), end - snap), end)
        }
        return (start, max(min(rounded(second), limit), start + snap))
    }

    /// The entries that a new entry from `start` to `end` overlaps, in
    /// order, each with the part it overlaps as seconds after midnight on
    /// the new entry's day, which starts at `startSecond`. It compares real
    /// instants, so an entry from the day before that runs past midnight,
    /// or one recorded in another zone, counts. A running entry runs to
    /// `now`.
    public static func overlapping(
        start: Timestamp,
        end: Timestamp,
        startSecond: Int,
        entries: [ResolvedEntry],
        now: Timestamp
    ) -> [(entry: ResolvedEntry, range: Range<Int>)] {
        var found: [(entry: ResolvedEntry, range: Range<Int>)] = []
        for entry in entries {
            let from = max(start, entry.start)
            let to = min(end, entry.end ?? now)
            guard from < to else { continue }
            let lower = startSecond + Int(start.distance(to: from) / 1000)
            let upper = startSecond + Int(start.distance(to: to) / 1000)
            if lower < upper {
                found.append((entry, lower..<upper))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// `ranges` with the ones that touch or overlap joined, in order, for
    /// hatching time counted twice once each.
    public static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func rounded(_ second: Int) -> Int {
        Int((Double(second) / Double(snap)).rounded()) * snap
    }
}
