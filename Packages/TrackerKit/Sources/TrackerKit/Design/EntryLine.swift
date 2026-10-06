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
    /// What the line reads as, or nil when it isn't an entry.
    public private(set) var parts: EntryLineParts?
    /// Why the line isn't an entry, when it isn't.
    public private(set) var problem: String?
    /// Whether Return was pressed on a line that isn't an entry, until
    /// it's changed.
    public private(set) var refused = false
    /// What could replace the word at the insertion point.
    public private(set) var suggestions: [LineSuggestion] = []
    /// The suggestion Tab takes.
    public var highlightedSuggestion = 0
    /// Changes when the field should put its insertion point at
    /// `requestedCursor`, as after taking a suggestion.
    public private(set) var cursorRequest = 0
    public private(set) var requestedCursor: Int?

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
        let chosen = index ?? highlightedSuggestion
        guard suggestions.indices.contains(chosen) else { return false }
        let suggestion = suggestions[chosen]
        text = suggestion.text
        cursor = suggestion.cursor
        requestedCursor = suggestion.cursor
        cursorRequest += 1
        return true
    }

    /// Moves the highlight through the suggestions. Returns false when
    /// there are none, so the key does what it otherwise does.
    public func moveSuggestion(by step: Int) -> Bool {
        guard !suggestions.isEmpty else { return false }
        highlightedSuggestion = (highlightedSuggestion + step + suggestions.count) % suggestions.count
        return true
    }

    private func refresh() {
        if let entryID, !text.isEmpty {
            parts = model.entryLineParts(text, for: entryID)
            problem = parts == nil ? model.entryProblem(text, for: entryID) : nil
        } else {
            parts = nil
            problem = nil
        }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        if let entryID, !text.isEmpty {
            suggestions = model.suggestions(for: text, cursor: cursor ?? text.utf16.count, editing: entryID)
        } else {
            suggestions = []
        }
        highlightedSuggestion = 0
    }
}
