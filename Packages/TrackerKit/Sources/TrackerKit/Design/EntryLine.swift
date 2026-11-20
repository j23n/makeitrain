import Foundation
import Observation
import TrackerCore

/// A line typed over an entry, as the week's line editor and the iPhone's
/// entry sheet edit it, or for a new entry drawn on the week: what it
/// reads as, part by part, what could replace the word being typed, and
/// why it can't be applied.
@MainActor
@Observable
public final class EntryLineModel {
    public let model: AppModel
    /// The entry the line edits.
    public private(set) var entryID: UUID?
    /// The new entry the line makes, when it makes one instead.
    public private(set) var newEntry: NewEntryDraft?
    public var text = "" {
        didSet {
            if text != oldValue {
                refused = false
                refresh()
            }
        }
    }
    /// Where the insertion point is, as a UTF-16 offset; nil for the end.
    public var cursor: Int? {
        didSet {
            if cursor != oldValue {
                refreshSuggestions()
            }
        }
    }
    /// What the line means, for highlighting it.
    public private(set) var reading = CommandReading(text: "")
    /// What the line reads as, or nil when it isn't an entry.
    public private(set) var parts: EntryLineParts?
    /// Why the line isn't an entry, when it isn't.
    public private(set) var problem: String?
    /// Whether Return was pressed on a line that isn't an entry, until
    /// it's changed.
    public private(set) var refused = false
    /// What could replace the word at the insertion point.
    public private(set) var suggestions = LineSuggestionState()

    public init(model: AppModel) {
        self.model = model
    }

    /// The entry, as it is now.
    public var entry: ResolvedEntry? {
        entryID.flatMap { id in model.resolved.first { $0.id == id } }
    }

    /// Whether the line is the entry's own, unchanged.
    public var isUnchanged: Bool {
        entry.map { model.line(for: $0) } == text
    }

    /// Edits another entry, or none.
    public func show(_ entryID: UUID?) {
        self.entryID = entryID
        newEntry = nil
        revert()
    }

    /// Makes a new entry, starting with the draft's day and times.
    public func showNew(_ draft: NewEntryDraft) {
        entryID = nil
        newEntry = draft
        revert()
    }

    /// Follows the new entry's times as it's dragged on the week: the line
    /// gets the new day and times while it still starts with the old ones,
    /// and keeps the rest.
    public func retime(_ draft: NewEntryDraft) {
        guard let old = newEntry, old != draft else { return }
        let before = model.line(for: old)
        newEntry = draft
        if text.hasPrefix(before) {
            text = model.line(for: draft) + text.dropFirst(before.count)
        } else {
            refresh()
        }
    }

    /// Puts the entry's line back, or the new entry's day and times.
    public func revert() {
        let line = entry.map { model.line(for: $0) } ?? newEntry.map { model.line(for: $0) } ?? ""
        if text == line {
            refresh()
        } else {
            text = line
        }
        cursor = nil
        refused = false
    }

    /// Changes the entry to what the line says. Returns false, and says
    /// why, when the line isn't an entry.
    @discardableResult
    public func apply(undoManager: UndoManager?) -> Bool {
        let applied = if let newEntry {
            model.addEntry(line: text, for: newEntry, undoManager: undoManager)
        } else if let entryID {
            model.apply(line: text, to: entryID, undoManager: undoManager)
        } else {
            false
        }
        guard applied else {
            // Read it again, in case it was read before the data changed.
            refresh()
            refused = true
            return false
        }
        return true
    }

    /// Puts the highlighted suggestion, or the one at `index`, in place of
    /// the word. Returns whether there was one.
    @discardableResult
    public func acceptSuggestion(at index: Int? = nil) -> Bool {
        guard let suggestion = suggestions.suggestion(at: index) else { return false }
        suggestions.requestCursor(after: suggestion)
        text = suggestion.text
        cursor = suggestion.cursor
        return true
    }

    /// What Tab does: takes the highlighted suggestion. Returns whether
    /// there was one, so the key otherwise does what it does.
    public func tab() -> Bool {
        acceptSuggestion()
    }

    /// What Up does: moves the highlight through the suggestions.
    public func up() -> Bool {
        moveHighlight(by: -1)
    }

    /// What Down does: moves the highlight the other way.
    public func down() -> Bool {
        moveHighlight(by: 1)
    }

    /// Moves the highlight through the suggestions, or returns false when
    /// there are none. It writes the suggestions only when the highlight
    /// moves, so a key that moves nothing redraws nothing.
    private func moveHighlight(by step: Int) -> Bool {
        guard let index = suggestions.highlight(movedBy: step) else { return false }
        if index != suggestions.highlighted {
            suggestions.highlight(index)
        }
        return true
    }

    private func refresh() {
        if let newEntry, !text.isEmpty {
            let read = model.readNewEntryLine(text, for: newEntry)
            reading = read.reading
            parts = read.parts
            problem = read.problem
        } else if let entryID, !text.isEmpty {
            let read = model.readEntryLine(text, for: entryID)
            reading = read.reading
            parts = read.parts
            problem = read.problem
        } else {
            reading = CommandReading(text: text)
            parts = nil
            problem = nil
        }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        if newEntry != nil, !text.isEmpty {
            suggestions.reset(to: model.suggestions(for: text, cursor: cursor ?? text.utf16.count))
        } else if let entryID, !text.isEmpty {
            suggestions.reset(to: model.suggestions(for: text, cursor: cursor ?? text.utf16.count, editing: entryID))
        } else {
            suggestions.reset(to: [])
        }
    }
}
