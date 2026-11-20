import Foundation
import TrackerCore

/// An entry drawn on the week's grid that isn't saved yet: its day and
/// times, which its line starts with, until the line is saved.
public struct NewEntryDraft: Hashable, Sendable {
    /// The id the entry gets when it's saved.
    public var id: UUID
    public var day: LocalDate
    /// Seconds after midnight in `timeZone`.
    public var startSecond: Int
    public var endSecond: Int
    /// The zone it's drawn and recorded in: the device's.
    public var timeZone: String

    public init(id: UUID = UUID(), day: LocalDate, startSecond: Int, endSecond: Int, timeZone: String) {
        self.id = id
        self.day = day
        self.startSecond = startSecond
        self.endSecond = endSecond
        self.timeZone = timeZone
    }

    public var start: Timestamp {
        Timestamp(date: day, secondOfDay: startSecond, zone: timeZone)
    }

    public var end: Timestamp {
        Timestamp(date: day, secondOfDay: endSecond, zone: timeZone)
    }
}

extension AppModel {
    /// A new entry drawn from `startSecond` to `endSecond` on `day`, in the
    /// device's zone.
    public func newEntryDraft(on day: LocalDate, startSecond: Int, endSecond: Int) -> NewEntryDraft {
        NewEntryDraft(day: day, startSecond: startSecond, endSecond: endSecond, timeZone: environment.timeZone())
    }

    /// The latest a new entry on `day` can end, in seconds after midnight
    /// in the device's zone: now on today.
    public func latestNewEntryEnd(on day: LocalDate) -> Int {
        NewEntrySpan.latest(on: day, now: environment.now(), zone: environment.timeZone())
    }

    /// The line a new entry starts with: its day and times.
    public func line(for draft: NewEntryDraft) -> String {
        Ledger.newEntryLine(day: draft.day, startSecond: draft.startSecond, endSecond: draft.endSecond, today: today)
    }

    /// The entries a new entry overlaps, in order, each with the part it
    /// overlaps as seconds after midnight on the new entry's day. Entries
    /// from the day before and ones recorded in other zones count.
    public func overlaps(of draft: NewEntryDraft) -> [(entry: ResolvedEntry, range: Range<Int>)] {
        NewEntrySpan.overlapping(start: draft.start, end: draft.end, startSecond: draft.startSecond, entries: resolved, now: now)
    }

    /// The parts of a new entry that other entries already take, joined
    /// where they touch, for hatching each once.
    public func overlapRanges(of draft: NewEntryDraft) -> [Range<Int>] {
        NewEntrySpan.merged(overlaps(of: draft).map(\.range))
    }

    /// A line typed for a new entry, read in its zone: the reading, what
    /// it makes of the entry, or else why it can't be one. A line without
    /// times keeps the draft's, and one with only a start keeps its end.
    func readNewEntryLine(_ line: String, for draft: NewEntryDraft) -> (reading: CommandReading, parts: EntryLineParts?, problem: String?) {
        var context = commandContext
        context.timeZone = draft.timeZone
        // A new entry never starts or stops a timer, so the running one
        // mustn't turn a line away as running already or as starting
        // before it.
        context.resolved.removeAll { $0.isRunning }
        let reading = CommandReading(line, in: context)
        let zone = draft.timeZone
        switch reading.primary {
        case let .log(entry, start, end)?:
            return (reading, EntryLineParts(start: start, end: end, zone: zone, draft: entry), nil)
        case let .start(entry, start, end)?:
            guard reading.tokens.contains(where: { $0.kind == .time }) else {
                return (reading, EntryLineParts(start: draft.start, end: draft.end, zone: zone, draft: entry), nil)
            }
            let stop = end ?? draft.end
            if stop > start {
                return (reading, EntryLineParts(start: start, end: stop, zone: zone, draft: entry), nil)
            }
            return (reading, nil, CommandText.message(.endsBeforeStart, zone: zone))
        default:
            break
        }
        if let problem = reading.problem {
            return (reading, nil, CommandText.message(problem, zone: zone))
        }
        return (reading, nil, "Can't read this as an entry. Start with its times, then its project, tags and note.")
    }

    /// Saves a new entry as its line says, with the draft's id. Returns
    /// false when the line isn't an entry or nothing could be saved.
    @discardableResult
    public func addEntry(line: String, for draft: NewEntryDraft, undoManager: UndoManager?) -> Bool {
        guard let parts = readNewEntryLine(line, for: draft).parts, let end = parts.end else { return false }
        return edit("Log Entry", undoManager: undoManager) { ledger, now in
            ledger.addEntry(TimeEntry(
                id: draft.id,
                projectID: parts.draft.projectID,
                start: parts.start,
                end: end,
                timeZone: parts.zone,
                tags: parts.draft.tags,
                note: parts.draft.note,
                updated: now
            ), now: now)
        }
    }
}
