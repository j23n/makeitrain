import Foundation

/// Something in the logged time that probably needs correcting: an
/// overlap, a timer left running, an entry with no project, or a calendar
/// event that isn't logged. Like overlaps, corrections are worked out when
/// displaying and never stored; skipping one is remembered on the device.
public struct Correction: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case overlap(Overlap)
        /// An entry ran overnight or more than 12 hours, or the running timer
        /// has. `overnight` says it ran past midnight into the morning.
        case ranLong(id: UUID, overnight: Bool)
        /// A stopped entry without a project.
        case noProject(id: UUID)
        /// A calendar event, linked to a project through its calendar, that
        /// isn't logged: the entry logging it would add.
        case notLogged(TimeEntry)
    }

    public var kind: Kind
    /// The day it's on.
    public var day: LocalDate
    /// When it starts, for putting corrections in order.
    public var start: Timestamp
    /// The fixes to offer, the one to suggest first. Empty when it takes a
    /// choice, as of a project for an entry without one.
    public var fixes: [CorrectionFix]
    /// Stays the same while the entries it's about do, so skipping it can
    /// be remembered.
    public var id: String

    public init(kind: Kind, day: LocalDate, start: Timestamp, fixes: [CorrectionFix], id: String) {
        self.kind = kind
        self.day = day
        self.start = start
        self.fixes = fixes
        self.id = id
    }

    /// The fix to suggest, if there is one.
    public var suggestion: CorrectionFix? {
        fixes.first
    }

    /// The entries it's about.
    public var entryIDs: [UUID] {
        switch kind {
        case let .overlap(overlap): [overlap.earlier, overlap.later]
        case let .ranLong(id, _), let .noProject(id): [id]
        case .notLogged: []
        }
    }
}

/// A way to correct something.
public enum CorrectionFix: Hashable, Sendable {
    case overlap(OverlapFix)
    /// Ends an entry at a time, which stops it if it's running.
    case end(id: UUID, at: Timestamp)
    /// Gives an entry a project.
    case assign(id: UUID, projectID: UUID)
    /// Adds an entry, as for a calendar event.
    case add(TimeEntry)
}

extension Ledger {
    /// Applies a correction's fix.
    @discardableResult
    public mutating func apply(_ fix: CorrectionFix, now: Timestamp) -> Changes {
        switch fix {
        case let .overlap(overlapFix):
            return apply(overlapFix, now: now)
        case let .end(id, time):
            return updateEntry(id, now: now) { entry in
                entry.end = max(time.wholeSeconds, entry.start)
            }
        case let .assign(id, projectID):
            return updateEntry(id, now: now) { $0.projectID = projectID }
        case let .add(entry):
            return addEntry(entry, now: now)
        }
    }
}

public enum Corrections {
    /// The longest an entry runs before it counts as left running.
    public static let longest: Int64 = 12 * 3_600_000

    /// What needs correcting on some days, in order.
    ///
    /// `events` are the calendar events on those days in this device's
    /// linked calendars, and `calendarProjects` has each linked calendar's
    /// project, by calendar id; events whose time is mostly logged to their
    /// project already aren't listed. New entries are recorded in
    /// `timeZone`.
    public static func find(
        on days: ClosedRange<LocalDate>,
        ledger: Ledger,
        resolved: [ResolvedEntry],
        events: [CalendarImport.Event] = [],
        calendarProjects: [String: UUID] = [:],
        timeZone: String,
        now: Timestamp
    ) -> [Correction] {
        let widened = days.lowerBound.adding(days: -1)...days.upperBound
        let matcher = EntryFilter(range: widened).matcher(in: ledger)
        let nearby = resolved.filter(matcher)
        let inRange = nearby.filter { days.contains($0.entry.day) }
        var result: [Correction] = []

        // Overlaps, including with an entry from the day before.
        let byID = Dictionary(nearby.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for overlap in Overlaps.analyze(nearby, now: now).overlaps {
            guard let later = byID[overlap.later], days.contains(later.entry.day) else { continue }
            result.append(Correction(
                kind: .overlap(overlap),
                day: later.entry.day,
                start: later.start,
                fixes: overlap.fixes.map(CorrectionFix.overlap),
                id: "overlap \(overlap.earlier) \(overlap.later)"
            ))
        }

        // Timers left running.
        let usual = UsualEnd(resolved: resolved, before: days.upperBound.adding(days: 1))
        for entry in inRange {
            guard let overnight = ranLong(entry, now: now) else { continue }
            result.append(Correction(
                kind: .ranLong(id: entry.id, overnight: overnight),
                day: entry.entry.day,
                start: entry.start,
                fixes: usual.ends(for: entry, now: now).map { CorrectionFix.end(id: entry.id, at: $0) },
                id: "long \(entry.id)"
            ))
        }

        // Entries without a project, where an entry with the same note has
        // one: suggest that project.
        let unassigned = inRange.filter { $0.entry.projectID == nil && !$0.isRunning }
        if !unassigned.isEmpty {
            var projectOfNote: [String: UUID] = [:]
            for entry in resolved {
                guard let projectID = entry.entry.projectID, !entry.entry.note.isEmpty, !ledger.isArchived(project: projectID) else { continue }
                projectOfNote[entry.entry.note.lowercased()] = projectID
            }
            for entry in unassigned {
                let suggested = entry.entry.note.isEmpty ? nil : projectOfNote[entry.entry.note.lowercased()]
                result.append(Correction(
                    kind: .noProject(id: entry.id),
                    day: entry.entry.day,
                    start: entry.start,
                    fixes: suggested.map { [CorrectionFix.assign(id: entry.id, projectID: $0)] } ?? [],
                    id: "project \(entry.id)"
                ))
            }
        }

        // Calendar events not logged.
        if !events.isEmpty, !calendarProjects.isEmpty {
            let plan = CalendarImport.plan(events, projects: calendarProjects, into: ledger, timeZone: timeZone, now: now)
            for entry in plan.entries where days.contains(entry.day) {
                guard let end = entry.end, !isLogged(entry, end: end, in: nearby, now: now) else { continue }
                result.append(Correction(
                    kind: .notLogged(entry),
                    day: entry.day,
                    start: entry.start,
                    fixes: [.add(entry)],
                    id: "event \(entry.id)"
                ))
            }
        }

        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Applies the suggested fix of each correction in `ids`, one after
    /// another, working the corrections out again after each, so a fix
    /// that an earlier one made unnecessary isn't applied.
    @discardableResult
    public static func applySuggestions(
        _ ids: Set<String>,
        to ledger: inout Ledger,
        on days: ClosedRange<LocalDate>,
        events: [CalendarImport.Event] = [],
        calendarProjects: [String: UUID] = [:],
        timeZone: String,
        now: Timestamp
    ) -> Changes {
        var remaining = ids
        var changes = Changes()
        while !remaining.isEmpty {
            let current = find(
                on: days,
                ledger: ledger,
                resolved: ledger.resolvedEntries(),
                events: events,
                calendarProjects: calendarProjects,
                timeZone: timeZone,
                now: now
            )
            guard let next = current.first(where: { remaining.contains($0.id) && $0.suggestion != nil }),
                  let fix = next.suggestion
            else { break }
            remaining.remove(next.id)
            changes.formUnion(ledger.apply(fix, now: now))
        }
        return changes
    }

    /// Whether an entry ran too long: nil if not, otherwise whether it ran
    /// past midnight into the morning. A running timer counts up to now.
    public static func ranLong(_ entry: ResolvedEntry, now: Timestamp) -> Bool? {
        let end = entry.end ?? now
        let length = entry.start.distance(to: end)
        let zone = entry.entry.timeZone
        let endLocal = end.local(in: zone)
        let overnight = endLocal.date > entry.entry.day && (endLocal.date > entry.entry.day.adding(days: 1) || endLocal.millisecondOfDay >= 5 * 3_600_000)
        if length > longest || overnight {
            return overnight
        }
        return nil
    }

    /// Whether at least half of an event's time is logged to its project.
    static func isLogged(_ event: TimeEntry, end: Timestamp, in entries: [ResolvedEntry], now: Timestamp) -> Bool {
        let length = event.start.distance(to: end)
        guard length > 0 else { return true }
        var covered: [TimeSpan] = []
        for entry in entries where entry.entry.projectID == event.projectID {
            let from = max(entry.start, event.start)
            let to = min(entry.end ?? now, end)
            if from < to {
                covered.append(TimeSpan(start: from, end: to))
            }
        }
        let total = covered.reduce(0) { $0 + $1.duration } - Overlaps.doubleCounted(covered)
        return total * 2 >= length
    }
}

/// When the working day usually ends: the middle of the last ends of the
/// four weeks of days before a day, leaving out entries that ran long.
/// 18:00 when there's nothing to go by.
struct UsualEnd {
    /// Seconds after midnight.
    var second: Int

    init(resolved: [ResolvedEntry], before day: LocalDate) {
        let first = day.adding(days: -28)
        var lastEnds: [LocalDate: Int] = [:]
        for entry in resolved.reversed() {
            guard let end = entry.end else { continue }
            let entryDay = entry.entry.day
            if entryDay < first.adding(days: -2) { break }
            guard entryDay >= first, entryDay < day, Corrections.ranLong(entry, now: end) == nil else { continue }
            let endLocal = end.local(in: entry.entry.timeZone)
            guard endLocal.date == entryDay else { continue }
            let second = endLocal.millisecondOfDay / 1000
            lastEnds[entryDay] = max(lastEnds[entryDay] ?? 0, second)
        }
        let sorted = lastEnds.values.sorted()
        second = sorted.isEmpty ? 18 * 3600 : sorted[sorted.count / 2]
    }

    /// Times to end an entry that ran long, the likeliest first: when the
    /// day usually ends, and an hour either side, each after the start and
    /// before the entry's end. An entry that started after the usual end
    /// gets an hour.
    func ends(for entry: ResolvedEntry, now: Timestamp) -> [Timestamp] {
        let zone = entry.entry.timeZone
        let day = entry.entry.day
        let end = entry.end ?? now
        let earliest = entry.start.adding(seconds: 15 * 60)
        let usual = rounded(Timestamp(date: day, secondOfDay: second, zone: zone))
        var candidates: [Timestamp] = []
        if usual > earliest {
            candidates = [usual, usual.adding(seconds: -3600), usual.adding(seconds: 3600)]
        } else {
            candidates = [rounded(entry.start.adding(seconds: 3600))]
        }
        return candidates.filter { $0 > entry.start && $0 < end }
    }

    /// A time on a multiple of five minutes.
    private func rounded(_ time: Timestamp) -> Timestamp {
        let step: Int64 = 300_000
        return Timestamp(milliseconds: (time.milliseconds + step / 2).floorDivided(by: step) * step)
    }
}

/// Time logged per day and project, worked out once when the entries
/// change, for calendars and charts that show many days. An entry counts
/// on the day it starts, as in reports.
public struct DayTotals: Hashable, Sendable {
    /// Stopped entries' time by day and project.
    private var days: [LocalDate: [UUID?: Int64]] = [:]
    /// The running timer, counted up to the time asked about.
    public private(set) var running: ResolvedEntry?

    public init(_ resolved: [ResolvedEntry] = []) {
        for entry in resolved {
            guard let end = entry.end else {
                running = entry
                continue
            }
            days[entry.entry.day, default: [:]][entry.entry.projectID, default: 0] += max(0, entry.start.distance(to: end))
        }
    }

    /// A day's time by project, the running timer up to `now` if `now` is
    /// given.
    public func projects(on day: LocalDate, now: Timestamp? = nil) -> [UUID?: Int64] {
        var result = days[day] ?? [:]
        if let now, let running, running.entry.day == day {
            result[running.entry.projectID, default: 0] += running.duration(now: now)
        }
        return result
    }

    /// A day's time, the running timer up to `now` if `now` is given.
    public func total(on day: LocalDate, now: Timestamp? = nil) -> Int64 {
        projects(on: day, now: now).values.reduce(0, +)
    }

    /// The time on some days, as `total(on:now:)` counts it.
    public func total(in range: ClosedRange<LocalDate>, now: Timestamp? = nil) -> Int64 {
        range.days.reduce(0) { $0 + total(on: $1, now: now) }
    }
}
