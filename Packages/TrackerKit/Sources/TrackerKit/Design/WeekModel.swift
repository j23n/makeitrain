import Foundation
import Observation
import TrackerCore

/// An entry a suggestion would add: a logged event, or part of a split
/// entry.
public struct SuggestedAddition: Identifiable, Hashable {
    /// The suggestion's correction's number.
    public var number: Int
    public var entry: TimeEntry
    /// Whether it's a calendar event's.
    public var isEvent: Bool

    public var id: UUID { entry.id }
}

/// What a correction's suggested fix would change, for drawing it in place
/// on the week: the entries it changes, and those it adds.
public struct CorrectionPreview: Identifiable, Hashable {
    /// Its number on the week, from 1.
    public var number: Int
    public var correction: Correction
    /// What the suggested fix changes; empty when there's no suggestion.
    public var diff: LedgerDiff

    public var id: String { correction.id }
}

/// The days a week, day or month screen shows, with what needs correcting
/// on them and what accepting the suggestions would make of them. It's
/// worked out once when the data or the days change, not on every redraw.
@MainActor
@Observable
public final class WeekModel {
    public let model: AppModel
    public private(set) var days: ClosedRange<LocalDate>
    /// What needs correcting, in order, without what was skipped.
    public private(set) var corrections: [Correction] = []
    /// What each correction's suggestion would change.
    public private(set) var previews: [CorrectionPreview] = []
    /// Time per day and project if every suggestion were accepted, or nil
    /// when none would change anything.
    public private(set) var correctedTotals: DayTotals?
    /// The correction chosen in the list, by id.
    public var selectedCorrection: String?
    /// The entry chosen on the week.
    public var selectedEntry: UUID?
    /// The entries on each day shown and the day before, as they're
    /// resolved, by day.
    public private(set) var entries: [LocalDate: [ResolvedEntry]] = [:]

    @ObservationIgnored private var loadedRevision = -1
    @ObservationIgnored private var loadedSkips: [String] = []

    public init(model: AppModel, days: ClosedRange<LocalDate>) {
        self.model = model
        self.days = days
        reload()
    }

    /// Shows other days.
    public func show(_ days: ClosedRange<LocalDate>) {
        guard days != self.days else { return }
        self.days = days
        reload()
    }

    /// Works everything out again if the data or the skipped corrections
    /// changed since last time.
    public func refresh() {
        guard loadedRevision != model.revision || loadedSkips != model.preferences.skippedCorrections else { return }
        reload()
    }

    public func reload() {
        loadedRevision = model.revision
        loadedSkips = model.preferences.skippedCorrections
        let widened = days.lowerBound.adding(days: -1)...days.upperBound
        let matches = EntryFilter(range: widened).matcher(in: model.ledger)
        entries = Dictionary(grouping: model.resolved.filter(matches), by: { $0.entry.day })
        let found = model.corrections(on: days)
        corrections = found
        let now = model.environment.now()
        previews = found.enumerated().map { index, correction in
            var copy = model.ledger
            if let fix = correction.suggestion {
                copy.apply(fix, now: now)
            }
            return CorrectionPreview(number: index + 1, correction: correction, diff: copy.diff(from: model.ledger))
        }
        if found.contains(where: { $0.suggestion != nil }) {
            let corrected = model.ledgerWithSuggestions(of: found, on: days)
            correctedTotals = DayTotals(corrected.resolvedEntries())
        } else {
            correctedTotals = nil
        }
        if !found.contains(where: { $0.id == selectedCorrection }) {
            selectedCorrection = found.first?.id
        }
        if let entry = selectedEntry, model.ledger.entries[entry]?.isDeleted != false {
            selectedEntry = nil
        }
    }

    /// The selected correction's preview.
    public var selectedPreview: CorrectionPreview? {
        previews.first { $0.id == selectedCorrection } ?? previews.first
    }

    /// Moves the selection to the next correction, or the one before.
    public func moveSelection(by step: Int) {
        guard !previews.isEmpty else { return }
        let index = previews.firstIndex { $0.id == selectedCorrection } ?? 0
        let next = min(max(index + step, 0), previews.count - 1)
        selectedCorrection = previews[next].id
    }

    /// Accepts the selected correction's suggestion.
    public func acceptSelected(undoManager: UndoManager?) {
        guard let fix = selectedPreview?.correction.suggestion else { return }
        model.apply(fix, undoManager: undoManager)
        reload()
    }

    /// Skips the selected correction on this device.
    public func skipSelected() {
        guard let id = selectedPreview?.id else { return }
        let index = previews.firstIndex { $0.id == id } ?? 0
        model.preferences.skip(id)
        reload()
        if !previews.isEmpty {
            selectedCorrection = previews[min(index, previews.count - 1)].id
        }
    }

    /// Accepts every suggestion, as one step to undo.
    public func acceptAll(undoManager: UndoManager?) {
        model.acceptSuggestions(of: corrections, on: days, undoManager: undoManager)
        reload()
    }

    /// The entries on a day, as they're resolved.
    public func entries(on day: LocalDate) -> [ResolvedEntry] {
        entries[day] ?? []
    }

    /// The time on a day, with the running timer up to now.
    public func total(on day: LocalDate) -> Int64 {
        model.dayTotals.total(on: day, now: model.now)
    }

    /// The time on a day if the suggestions were accepted, when that's
    /// different.
    public func correctedTotal(on day: LocalDate) -> Int64? {
        guard let correctedTotals else { return nil }
        let corrected = correctedTotals.total(on: day, now: model.now)
        return corrected == total(on: day) ? nil : corrected
    }

    /// The days' total, and with the suggestions accepted when that's
    /// different.
    public var totals: (total: Int64, corrected: Int64?) {
        let total = model.dayTotals.total(in: days, now: model.now)
        guard let correctedTotals else { return (total, nil) }
        let corrected = correctedTotals.total(in: days, now: model.now)
        return (total, corrected == total ? nil : corrected)
    }

    /// The entry as a suggestion would leave it, if one would change it,
    /// with that suggestion's number.
    public func suggestedChange(of entryID: UUID) -> (number: Int, before: TimeEntry, after: TimeEntry)? {
        for preview in previews {
            if let change = preview.diff.entries.first(where: { $0.before?.id == entryID }), let before = change.before {
                return (preview.number, before, change.after)
            }
        }
        return nil
    }

    /// What an entry's block says when it ran long, such as "ran overnight
    /// · 19:25", "ran 13:10" or "running 12:40"; nil when it didn't.
    public func ranLongNote(for entry: ResolvedEntry) -> String? {
        for preview in previews {
            if case let .ranLong(id, overnight) = preview.correction.kind, id == entry.id {
                let length = Format.duration(model.duration(of: entry))
                if entry.isRunning { return "running \(length)" }
                return overnight ? "ran overnight · \(length)" : "ran \(length)"
            }
        }
        return nil
    }

    /// Entries suggestions would add, with their numbers: logged events and
    /// the parts of split entries.
    public var suggestedAdditions: [SuggestedAddition] {
        var result: [SuggestedAddition] = []
        for preview in previews {
            let isEvent: Bool = if case .notLogged = preview.correction.kind { true } else { false }
            for change in preview.diff.entries where change.before == nil {
                result.append(SuggestedAddition(number: preview.number, entry: change.after, isEvent: isEvent))
            }
        }
        return result
    }
}
