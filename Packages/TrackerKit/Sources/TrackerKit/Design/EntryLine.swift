import Foundation
import Observation
import TrackerCore

/// A line typed over an entry, as the week's line editor and the iPhone's
/// entry sheet edit it: what it reads as, part by part, what could replace
/// the word being typed, and why it can't be applied.
@MainActor
@Observable
public final class EntryLineModel {
    public let model: AppModel
    /// The entry the line edits.
    public private(set) var entryID: UUID?
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
        revert()
    }

    /// Puts the entry's line back.
    public func revert() {
        let line = entry.map { model.line(for: $0) } ?? ""
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
        guard let entryID, model.apply(line: text, to: entryID, undoManager: undoManager) else {
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
        guard let suggestion = suggestions.take(at: index) else { return false }
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
        suggestions.move(by: -1)
    }

    /// What Down does: moves the highlight the other way.
    public func down() -> Bool {
        suggestions.move(by: 1)
    }

    private func refresh() {
        if let entryID, !text.isEmpty {
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
        if let entryID, !text.isEmpty {
            suggestions.reset(to: model.suggestions(for: text, cursor: cursor ?? text.utf16.count, editing: entryID))
        } else {
            suggestions.reset(to: [])
        }
    }
}
