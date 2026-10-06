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
                refresh()
            }
        }
    }
    /// What the line means.
    public private(set) var reading = CommandReading(text: "")
    /// What Return would change.
    public private(set) var preview: CommandPreview?
    /// What Option-Return would change.
    public private(set) var alternatePreview: CommandPreview?
    /// What happened when a line last ran, such as a problem, until the
    /// next keystroke.
    public var message: String?
    /// Whether today's entries are listed, as Down shows them.
    public var showsToday = false
    /// The entries "find" lists.
    public private(set) var found: [ResolvedEntry] = []

    public let model: AppModel
    @ObservationIgnored private var historyIndex: Int?
    @ObservationIgnored private var draftBeforeHistory = ""

    public init(model: AppModel) {
        self.model = model
    }

    /// Reads the line again, as after the data changed.
    public func refresh() {
        message = nil
        reading = model.read(text)
        preview = nil
        alternatePreview = nil
        found = []
        switch reading.primary {
        case let .find(query)?:
            found = model.find(query)
        case let command?:
            preview = model.preview(command)
        case nil:
            break
        }
        if let alternate = reading.alternate {
            alternatePreview = model.preview(alternate)
        }
        if !text.isEmpty {
            showsToday = false
        }
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
        text = history[index]
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
            text = history[index + 1]
        } else {
            historyIndex = nil
            text = draftBeforeHistory
        }
        return true
    }

    public func clear() {
        historyIndex = nil
        text = ""
        showsToday = false
    }

    /// Today's entries, the latest first, as Down lists them.
    public var todaysEntries: [ResolvedEntry] {
        let today = model.today
        return model.resolved.filter { $0.entry.day == today }.reversed()
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
                CommandChanges(model: model, command: command, preview: preview)
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
                DraftLabel(ledger: model.ledger, draft: EntryDraft(projectID: running.entry.projectID, tags: running.entry.tags, note: running.entry.note))
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
public struct DraftLabel: View {
    let ledger: Ledger
    let draft: EntryDraft

    public init(ledger: Ledger, draft: EntryDraft) {
        self.ledger = ledger
        self.draft = draft
    }

    public var body: some View {
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

/// What a command changes, in words: "Bookings ends at 10:40, after 1:10.
/// No gap, no overlap." or the times that change, struck through.
public struct CommandChanges: View {
    let model: AppModel
    let command: Command
    let preview: CommandPreview

    public init(model: AppModel, command: Command, preview: CommandPreview) {
        self.model = model
        self.command = command
        self.preview = preview
    }

    public var body: some View {
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
            guard let after = change.after else { continue }
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
                if case .start(_, let start, .none) = command, abs(start.distance(to: now)) < 60000 {
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
            guard let after = change.after else { continue }
            if change.isNew {
                let client = after.clientID.flatMap { ledger.clients[$0]?.name }
                result.append(Text("Adds \(after.name)") + Text(client.map { " to \($0)" } ?? "") + Text(", in \(Palette.name(of: after.color)). Repositories and a calendar can wait for its page."))
            }
        }
        if case .start(_, _, .none) = command, model.running != nil, preview.newOverlaps.isEmpty {
            result.append(Text("No gap, no overlap."))
        }
        for overlap in preview.newOverlaps {
            let other = [overlap.earlier, overlap.later]
                .compactMap { id in ledger.entries[id] }
                .first { entry in !preview.diff.entries.contains { $0.after?.id == entry.id } }
            if let other {
                let title = other.note.isEmpty ? ledger.projectTitle(other.projectID) : other.note
                result.append(Text("Overlaps \(title), \(Format.time(other.start, zone: other.timeZone))–\(other.end.map { Format.time($0, zone: other.timeZone) } ?? "now"), by \(Format.duration(overlap.duration)).")
                    .foregroundColor(Theme.amberText))
            }
        }
        return result
    }
}
