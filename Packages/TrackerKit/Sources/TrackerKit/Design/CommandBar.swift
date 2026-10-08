import Observation
import SwiftUI
import TrackerCore

/// The state behind a command line: what's typed, what it means, what it
/// would change, and the earlier lines Up brings back. The Mac's and the
/// iPhone's fields share it.
@MainActor
@Observable
public final class CommandLineModel {
    public var text: String = "" {
        didSet {
            if text != oldValue {
                if text != recalledLine {
                    recalledLine = nil
                }
                refresh()
            }
        }
    }
    /// What the line means.
    public private(set) var reading = CommandReading(text: "")
    /// What Return would change.
    public private(set) var preview: CommandPreview?
    /// What happened when a line last ran, such as a problem, until the
    /// next keystroke.
    public var message: String?
    /// Whether today's entries are listed, as Down shows them.
    public var showsToday = false
    /// The entries "find" lists.
    public private(set) var found: [ResolvedEntry] = []
    /// Where the insertion point is, as a UTF-16 offset; nil for the end.
    public var cursor: Int? {
        didSet {
            if cursor != oldValue {
                refreshSuggestions()
            }
        }
    }
    /// What could replace the word at the insertion point.
    public private(set) var suggestions = LineSuggestionState()

    public let model: AppModel
    @ObservationIgnored private var historyIndex: Int?
    @ObservationIgnored private var draftBeforeHistory = ""
    /// A line Up or Down brought back. It gets no suggestions until it's
    /// changed, so the keys keep going through the earlier lines.
    @ObservationIgnored private var recalledLine: String?

    public init(model: AppModel) {
        self.model = model
    }

    /// Reads the line again, as after the data changed.
    public func refresh() {
        message = nil
        reading = model.read(text)
        preview = nil
        found = []
        switch reading.primary {
        case let .find(query)?:
            found = model.find(query)
        case let command?:
            preview = model.preview(command)
        case nil:
            break
        }
        if !text.isEmpty {
            showsToday = false
        }
        refreshSuggestions()
    }

    /// Works out what could replace the word at the insertion point.
    private func refreshSuggestions() {
        if text.isEmpty || text == recalledLine {
            suggestions.reset(to: [])
        } else {
            suggestions.reset(to: model.suggestions(for: text, cursor: cursor ?? text.utf16.count))
        }
    }

    /// Puts the highlighted suggestion, or the one at `index`, in place of
    /// the word. Returns whether there was one.
    @discardableResult
    public func acceptSuggestion(at index: Int? = nil) -> Bool {
        guard let suggestion = suggestions.take(at: index) else { return false }
        historyIndex = nil
        text = suggestion.text
        cursor = suggestion.cursor
        return true
    }

    /// Runs the line. Returns whether something was done, so the field
    /// can close.
    @discardableResult
    public func submit(alternate: Bool, undoManager: UndoManager?) -> Bool {
        switch model.run(text, alternate: alternate, undoManager: undoManager) {
        case .done(.find):
            return false
        case .done:
            historyIndex = nil
            text = ""
            cursor = nil
            return true
        case let .problem(problem):
            message = CommandText.message(problem, zone: model.environment.timeZone())
            return false
        case .nothing:
            return false
        }
    }

    /// Takes the completion Tab offers. Returns whether there was one.
    public func complete() -> Bool {
        guard let completion = reading.completion else { return false }
        text = completion.text + " "
        cursor = nil
        return true
    }

    /// Brings back the line before, as Up does.
    public func previousLine() -> Bool {
        let history = model.preferences.history
        guard !history.isEmpty else { return false }
        if historyIndex == nil {
            draftBeforeHistory = text
        }
        let index = max(0, (historyIndex ?? history.count) - 1)
        historyIndex = index
        recalledLine = history[index]
        text = history[index]
        cursor = nil
        return true
    }

    /// Goes forward through earlier lines, as Down does, or lists today's
    /// entries when there are no more.
    public func nextLine() -> Bool {
        let history = model.preferences.history
        guard let index = historyIndex else {
            if text.isEmpty {
                showsToday.toggle()
                return true
            }
            return false
        }
        if index + 1 < history.count {
            historyIndex = index + 1
            recalledLine = history[index + 1]
            text = history[index + 1]
        } else {
            historyIndex = nil
            text = draftBeforeHistory
        }
        cursor = nil
        return true
    }

    /// What Tab does: takes the highlighted suggestion, or else the
    /// completion. Returns whether it did, so the key otherwise does what
    /// it does.
    public func tab() -> Bool {
        acceptSuggestion() || complete()
    }

    /// What Up does: moves the highlight through the suggestions, or else
    /// brings back the line before.
    public func up() -> Bool {
        suggestions.move(by: -1) || previousLine()
    }

    /// What Down does: moves the highlight the other way, or else goes
    /// forward through the earlier lines, or lists today's entries.
    public func down() -> Bool {
        suggestions.move(by: 1) || nextLine()
    }

    public func clear() {
        historyIndex = nil
        text = ""
        cursor = nil
        showsToday = false
    }

    /// Today's entries, the latest first, as Down lists them.
    public var todaysEntries: [ResolvedEntry] {
        let today = model.today
        return model.resolved.filter { $0.entry.day == today }.reversed()
    }
}

/// What could replace the word at a line's insertion point, the one Tab
/// takes, and where the insertion point goes once one is taken. The
/// command line and an entry's line keep one each.
public struct LineSuggestionState {
    /// The suggestions, the likeliest first.
    public private(set) var items: [LineSuggestion] = []
    /// The index of the one Tab takes.
    public private(set) var highlighted = 0
    /// Changes when the field should put its insertion point at
    /// `requestedCursor`, as after taking a suggestion.
    public private(set) var cursorRequest = 0
    public private(set) var requestedCursor: Int?

    /// Whether there's nothing to suggest.
    public var isEmpty: Bool {
        items.isEmpty
    }

    /// New suggestions, the first one highlighted.
    mutating func reset(to items: [LineSuggestion]) {
        self.items = items
        highlighted = 0
    }

    /// Moves the highlight. Returns false when there's nothing to move
    /// through, so the key does what it otherwise does.
    mutating func move(by step: Int) -> Bool {
        guard !items.isEmpty else { return false }
        highlighted = (highlighted + step + items.count) % items.count
        return true
    }

    /// The highlighted suggestion, or the one at `index`, if there is
    /// one, asking the field to put the insertion point after it.
    mutating func take(at index: Int?) -> LineSuggestion? {
        let chosen = index ?? highlighted
        guard items.indices.contains(chosen) else { return nil }
        requestedCursor = items[chosen].cursor
        cursorRequest += 1
        return items[chosen]
    }
}

/// Something to add to a line with a click or a tap: what could replace
/// the word being typed, a start, a time ago, a tag, or the completion of a
/// project's name; or, with nothing typed, a line run lately.
public struct LineChip: Identifiable {
    public enum Action {
        case append(String)
        case replace(String)
        case complete
        /// Takes the line's suggestion at this index.
        case suggestion(Int)
    }

    public var id: String
    public var title: String
    public var action: Action
    public var tint: ProjectTint?
    public var isTag = false
    /// Whether it's the suggestion Tab takes.
    public var isHighlighted = false
}

extension CommandLineModel {
    /// What to offer under the line: the suggestions for the word being
    /// typed, a start from when today's last entry ended, a time ago, a tag
    /// and the completion; with nothing typed, the lines run lately.
    public var chips: [LineChip] {
        guard !text.isEmpty else {
            var seen: Set<String> = []
            return model.preferences.history.reversed()
                .filter { seen.insert($0.lowercased()).inserted }
                .prefix(4)
                .map { LineChip(id: "again " + $0, title: $0, action: .replace($0)) }
        }
        var chips = suggestions.items.enumerated().map { index, suggestion -> LineChip in
            var tint: ProjectTint?
            switch suggestion.kind {
            case let .project(id):
                tint = model.ledger.tint(ofProject: id)
            case let .color(hex):
                tint = ProjectTint(hex: hex)
            default:
                tint = nil
            }
            let title = suggestion.detail.isEmpty ? suggestion.title : "\(suggestion.title) · \(suggestion.detail)"
            return LineChip(
                id: "suggestion \(index) \(suggestion.title)",
                title: title,
                action: .suggestion(index),
                tint: tint,
                isTag: suggestion.kind == .tag,
                isHighlighted: index == suggestions.highlighted
            )
        }
        let words = text.lowercased().split(separator: " ")
        if !words.contains("from"), let end = model.commandContext.lastEndToday {
            let time = Format.time(end, zone: model.environment.timeZone())
            chips.append(LineChip(id: "from", title: "from \(time)", action: .append("from \(time)")))
        }
        if !text.contains("-") {
            chips.append(LineChip(id: "ago", title: "−15m", action: .append("-15m")))
        }
        chips.append(LineChip(id: "tag", title: "#", action: .append("#"), isTag: true))
        if let completion = reading.completion {
            let projectID = model.resolved.first { $0.id == completion.entryID }?.entry.projectID
            chips.append(LineChip(
                id: "complete",
                title: "\(completion.text), from \(Format.weekday(completion.day))",
                action: .complete,
                tint: projectID.map { model.ledger.tint(ofProject: $0) }
            ))
        }
        return chips
    }

    /// Adds a chip to the line, or puts it in the line's place.
    public func apply(_ chip: LineChip) {
        switch chip.action {
        case let .append(words):
            text = text.isEmpty || text.hasSuffix(" ") ? text + words : text + " " + words
            cursor = nil
        case let .replace(line):
            text = line
            cursor = nil
        case .complete:
            _ = complete()
        case let .suggestion(index):
            acceptSuggestion(at: index)
        }
    }
}

/// What a line would do, under the command line: the action, with its
/// key, and what it changes, or why it can't.
public struct CommandPreviewView: View {
    let line: CommandLineModel
    /// Whether the action shows its key, as on the Mac. The iPhone has a
    /// button for it instead.
    let showsKey: Bool

    public init(line: CommandLineModel, showsKey: Bool = true) {
        self.line = line
        self.showsKey = showsKey
    }

    private var model: AppModel { line.model }
    private var zone: String { model.environment.timeZone() }

    public var body: some View {
        if let message = line.message {
            problemRow(message)
        } else if let command = line.reading.primary, let preview = line.preview {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    if showsKey {
                        KeyCap("⏎", inverted: true)
                    }
                    Text(CommandText.title(command, running: model.running, now: model.environment.now(), zone: zone))
                        .fontWeight(.semibold)
                    subject(command)
                }
                .lineLimit(1)
                CommandChanges(model: model, preview: preview)
                    .padding(.leading, showsKey ? 31 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentFill)
        } else if let problem = line.reading.problem, !line.text.isEmpty {
            problemRow(CommandText.message(problem, zone: zone))
        }
    }

    private func problemRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Theme.amber)
            Text(message)
                .foregroundStyle(Theme.amberText)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberWash)
    }

    /// The entry, project or client a command is about.
    @ViewBuilder
    private func subject(_ command: Command) -> some View {
        switch command {
        case let .start(draft, _, _), let .log(draft, _, _):
            DraftLabel(ledger: model.ledger, draft: draft)
        case .stop, .moveStart:
            if let running = model.running {
                DraftLabel(ledger: model.ledger, draft: EntryDraft(running.entry))
            }
        case let .addProject(name, client, _, _):
            HStack(spacing: 6) {
                Text(name).fontWeight(.semibold)
                switch client {
                case let .existing(id)?:
                    Text("to").foregroundStyle(Theme.text2)
                    Text(model.ledger.clients[id]?.name ?? "")
                case let .new(clientName)?:
                    Text("to new client").foregroundStyle(Theme.text2)
                    Text(clientName)
                case nil:
                    EmptyView()
                }
            }
        case let .addClient(name):
            Text(name).fontWeight(.semibold)
        case let .archive(target, _), let .rename(target, _):
            TargetLabel(ledger: model.ledger, target: target)
        case let .setColor(projectID, color):
            HStack(spacing: 6) {
                ProjectName(ledger: model.ledger, projectID: projectID)
                Image(systemName: "arrow.right").foregroundStyle(Theme.text3)
                TintDot(ProjectTint(hex: color))
                Text(Palette.name(of: color))
            }
        case let .merge(source, target):
            HStack(spacing: 6) {
                TargetLabel(ledger: model.ledger, target: source)
                Text("into").foregroundStyle(Theme.text2)
                TargetLabel(ledger: model.ledger, target: target)
            }
        case .find:
            EmptyView()
        }
    }
}

/// A project, its tags and a note, on one line.
struct DraftLabel: View {
    let ledger: Ledger
    let draft: EntryDraft

    var body: some View {
        HStack(spacing: 8) {
            ProjectName(ledger: ledger, projectID: draft.projectID)
                .fixedSize()
            ForEach(draft.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tag)
                    .fixedSize()
            }
            if !draft.note.isEmpty {
                Text(draft.note)
                    .foregroundStyle(Theme.text4)
                    .truncationMode(.tail)
            }
        }
        .lineLimit(1)
    }
}

/// A client or a project, by name.
struct TargetLabel: View {
    let ledger: Ledger
    let target: CommandTarget

    var body: some View {
        switch target {
        case let .project(id):
            ProjectName(ledger: ledger, projectID: id, weight: .semibold)
        case let .client(id):
            Text(ledger.clients[id]?.name ?? "Client")
                .fontWeight(.semibold)
        }
    }
}

/// What a command changes, in words: "Website ends at 10:40, after 1:10.
/// No gap, no overlap." or the times that change, struck through.
struct CommandChanges: View {
    let model: AppModel
    let preview: CommandPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                line
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
    }

    private var now: Timestamp { model.environment.now() }

    private var lines: [Text] {
        var result: [Text] = []
        let ledger = preview.after
        for change in preview.diff.entries {
            let after = change.after
            let zone = after.timeZone
            let projectName = after.projectID.flatMap { ledger.projects[$0]?.name }
            let name = Text(projectName ?? (after.note.isEmpty ? "Unassigned" : after.note))
            func time(_ value: Timestamp) -> Text {
                Text(Format.time(value, zone: zone)).foregroundColor(Theme.text)
            }
            func changed(_ value: Timestamp) -> Text {
                Text(Format.time(value, zone: zone)).fontWeight(.semibold).foregroundColor(Theme.amberText)
            }
            guard let before = change.before else {
                if after.isDeleted { continue }
                if let end = after.end {
                    result.append(name + Text(" ") + changed(after.start) + Text("–") + changed(end)
                        + Text(" (\(Format.duration(after.start.distance(to: end))))"))
                } else if abs(after.start.distance(to: now)) >= 60000 {
                    result.append(name + Text(" from ") + changed(after.start)
                        + Text(" (\(Format.duration(after.start.distance(to: now))))"))
                }
                continue
            }
            if after.isDeleted, !before.isDeleted {
                result.append(name + Text(" is removed"))
                continue
            }
            if before.end == nil, let end = after.end, before.start == after.start {
                if case .start(_, let start, .none) = preview.command, abs(start.distance(to: now)) < 60000 {
                    result.append(name + Text(" ends at ") + time(end) + Text(", after \(Format.duration(after.start.distance(to: end)))."))
                } else {
                    result.append(name + Text(" ") + time(after.start) + Text("–")
                        + Text("now").strikethrough(true, color: Theme.amber).foregroundColor(Theme.text3)
                        + Text(" ") + changed(end))
                }
                continue
            }
            var line = name + Text(" ")
            line = line + (before.start != after.start
                ? Text(Format.time(before.start, zone: zone)).strikethrough(true, color: Theme.amber).foregroundColor(Theme.text3) + Text(" ") + changed(after.start)
                : time(after.start))
            line = line + Text("–")
            if let end = after.end {
                line = line + (before.end != after.end
                    ? (before.end.map { Text(Format.time($0, zone: zone)) } ?? Text("now")).strikethrough(true, color: Theme.amber).foregroundColor(Theme.text3) + Text(" ") + changed(end)
                    : time(end))
            } else {
                line = line + Text("now")
            }
            if before.projectID != after.projectID {
                line = line + Text(", now ") + Text(ledger.projectTitle(after.projectID)).foregroundColor(Theme.amberText)
            }
            result.append(line)
        }
        for change in preview.diff.projects {
            let after = change.after
            if change.isNew {
                let client = after.clientID.flatMap { ledger.clients[$0]?.name }
                result.append(Text("Adds \(after.name)") + Text(client.map { " to \($0)" } ?? "") + Text(", in \(Palette.name(of: after.color))."))
            }
        }
        if case .start(_, _, .none) = preview.command, model.running != nil, preview.newOverlaps.isEmpty {
            result.append(Text("No gap, no overlap."))
        }
        for overlap in preview.newOverlaps {
            let other = [overlap.earlier, overlap.later]
                .compactMap { id in ledger.entries[id] }
                .first { entry in !preview.diff.entries.contains { $0.after.id == entry.id } }
            if let other {
                let title = other.note.isEmpty ? ledger.projectTitle(other.projectID) : other.note
                result.append(Text("Overlaps \(title), \(Format.time(other.start, zone: other.timeZone))–\(other.end.map { Format.time($0, zone: other.timeZone) } ?? "now"), by \(Format.duration(overlap.duration)).")
                    .foregroundColor(Theme.amberText))
            }
        }
        return result
    }
}
