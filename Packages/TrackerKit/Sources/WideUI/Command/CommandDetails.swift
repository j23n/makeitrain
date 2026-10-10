import SwiftUI
import TrackerCore
import TrackerKit

/// What's under a command line, the same in the menu bar's popover, the
/// shortcut's panel and the main window: the suggestions for the word being
/// typed, what Return would do, what "find" found or, with nothing typed,
/// today's entries, and the keys to know.
public struct CommandDetails: View {
    let line: CommandLineModel
    /// Whether it goes on in the field's own box, as in the popover, where
    /// a line sets off its first part from the field, rather than in a box
    /// of its own, as under the main window's field.
    let continuesField: Bool
    /// Picks a listed entry when it's clicked, if anything does.
    let select: ((ResolvedEntry) -> Void)?

    public init(line: CommandLineModel, continuesField: Bool = true, select: ((ResolvedEntry) -> Void)? = nil) {
        self.line = line
        self.continuesField = continuesField
        self.select = select
    }

    public var body: some View {
        let suggests = !line.suggestions.isEmpty
        let previews = line.hasPreview
        let listed = line.listedEntries(alwaysListsToday: true)
        VStack(spacing: 0) {
            if suggests {
                SuggestionStrip(suggestions: line.suggestions, ledger: line.model.ledger) { index in
                    line.acceptSuggestion(at: index)
                }
                .padding(.horizontal, 14)
                .padding(.top, continuesField ? 0 : 10)
                .padding(.bottom, 10)
            }
            if previews {
                if continuesField || suggests {
                    divider
                }
                CommandPreviewView(line: line)
            }
            if !listed.isEmpty {
                if continuesField || suggests || previews {
                    divider
                }
                EntryList(model: line.model, entries: listed, select: select)
            }
            if continuesField || suggests || previews || !listed.isEmpty {
                divider
            }
            hints
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.line)
    }

    /// The keys that do something with what's typed.
    private var hints: some View {
        HStack(spacing: 16) {
            // Tab takes a suggestion first.
            if let completion = line.reading.completion, line.suggestions.isEmpty {
                KeyHint("⇥", "\(completion.text), from \(Format.weekday(completion.day))")
                    .lineLimit(1)
            } else if case .addProject? = line.reading.alternate {
                KeyHint("⌥⏎", "add and start")
            }
            if line.text.isEmpty {
                if line.model.running != nil {
                    KeyHint("stop", "stop the timer")
                    KeyHint("from 10:30", "change its start")
                } else {
                    KeyHint("↑", "history")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}
