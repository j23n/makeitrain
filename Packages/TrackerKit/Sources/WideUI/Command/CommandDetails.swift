import SwiftUI
import TrackerCore
import TrackerKit

/// What's under a command line, the same in the menu bar's popover, the
/// shortcut's panel, the main window and on iPad and iPhone: with nothing
/// typed, lines to try and today's entries; while a line names only a
/// project, tags or a note, the earlier entries it could start again and
/// the line as typed; otherwise what the line would do, or what "find"
/// found; and on the Mac, the keys to know.
public struct CommandDetails: View {
    let line: CommandLineModel
    /// Whether it goes on in the field's own box, as in the popover, where
    /// a line sets off its first part from the field, rather than in a box
    /// of its own, as under the main window's field.
    let continuesField: Bool
    /// `.touch` for rows a finger can tap, as on iPad and iPhone, without
    /// the keys.
    let size: ChipLabel.Size
    /// Picks a listed entry when it's clicked, if anything does.
    let select: ((ResolvedEntry) -> Void)?
    /// Runs the line, as Return does, or with `alternate` as Option-Return
    /// does.
    let submit: (_ alternate: Bool) -> Void
    /// Gives the field the keyboard back after a line to try fills it.
    let refocus: () -> Void

    public init(
        line: CommandLineModel,
        continuesField: Bool = true,
        size: ChipLabel.Size = .regular,
        select: ((ResolvedEntry) -> Void)? = nil,
        submit: @escaping (_ alternate: Bool) -> Void,
        refocus: @escaping () -> Void = {}
    ) {
        self.line = line
        self.continuesField = continuesField
        self.size = size
        self.select = select
        self.submit = submit
        self.refocus = refocus
    }

    private var touch: Bool { size == .touch }
    private var model: AppModel { line.model }

    public var body: some View {
        let listed = line.listedEntries(alwaysListsToday: true)
        VStack(spacing: 0) {
            if continuesField {
                divider
            }
            if line.text.isEmpty {
                header("Try")
                examples
                if !listed.isEmpty {
                    divider
                    header("Today")
                    EntryList(model: model, entries: listed, size: size, select: select)
                }
            } else if !line.recalled.isEmpty {
                header("Start again")
                recalled
                divider
                asTyped
            } else {
                if line.hasPreview {
                    CommandPreviewView(line: line, showsKey: !touch)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if touch {
                                submit(false)
                            }
                        }
                }
                if !listed.isEmpty {
                    if line.hasPreview {
                        divider
                    }
                    EntryList(model: model, entries: listed, size: size, select: select)
                }
            }
            if touch {
                alternate
            } else {
                divider
                hints
            }
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.line)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .tracking(0.4)
            .font(.system(size: touch ? 12 : 11, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, touch ? 16 : 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    // MARK: - Nothing typed

    /// Lines to try, each with what it does. Clicking one puts it in the
    /// line, to change or run.
    private var examples: some View {
        let examples = Array(model.commandExamples.prefix(touch ? 5 : 8))
        return VStack(spacing: 0) {
            ForEach(examples, id: \.line) { example in
                Button {
                    line.text = example.line
                    refocus()
                } label: {
                    HStack(spacing: 12) {
                        ReadingText(reading: example.reading, ledger: model.ledger)
                            .font(.system(size: touch ? 14.5 : 12.5, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(example.meaning)
                            .font(.system(size: touch ? 13 : 12))
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, touch ? 16 : 14)
                    .frame(height: touch ? 44 : 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Typing

    /// The earlier entries the line could start again, the highlighted one
    /// marked. Clicking one starts it.
    private var recalled: some View {
        VStack(spacing: touch ? 0 : 1) {
            ForEach(Array(line.recalled.enumerated()), id: \.element.id) { index, entry in
                Button {
                    line.recallIndex = index
                    submit(false)
                } label: {
                    recalledRow(entry, highlighted: line.recallIndex == index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Start again: \(model.ledger.projectTitle(entry.entry.projectID)), \(model.ledger.title(of: entry.entry))"))
            }
        }
        .padding(.horizontal, touch ? 8 : 6)
        .padding(.bottom, 6)
    }

    private func recalledRow(_ entry: ResolvedEntry, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            ProjectName(ledger: model.ledger, projectID: entry.entry.projectID)
                .fixedSize()
            ForEach(entry.entry.tags, id: \.self) { tag in
                Text(Tags.typed(tag))
                    .foregroundStyle(Theme.tag)
                    .fixedSize()
            }
            if !entry.entry.note.isEmpty {
                Text(entry.entry.note)
                    .foregroundStyle(Theme.text4)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(when(entry.entry.day))
                .foregroundStyle(Theme.text2)
                .fixedSize()
            if highlighted, !touch {
                KeyCap("⏎")
            }
        }
        .font(.system(size: touch ? 15 : 12.5))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: touch ? 48 : 28)
        .background(RoundedRectangle(cornerRadius: touch ? 10 : 6).fill(highlighted ? Theme.accentFill : Color.clear))
        .contentShape(Rectangle())
    }

    /// "today", a weekday in the last week, or the day.
    private func when(_ day: LocalDate) -> String {
        let today = model.today
        if day == today {
            return "today"
        }
        return today.daysSince1970 - day.daysSince1970 < 7 ? Format.weekday(day) : Format.monthDay(day)
    }

    /// The line as typed, after the earlier entries: what it would do in
    /// full while it's highlighted, and in a row otherwise.
    @ViewBuilder
    private var asTyped: some View {
        if line.recallIndex == nil {
            CommandPreviewView(line: line, showsKey: !touch)
                .contentShape(Rectangle())
                .onTapGesture {
                    submit(false)
                }
        } else {
            Button {
                line.recallIndex = nil
                submit(false)
            } label: {
                HStack(spacing: 10) {
                    Text("› \(line.text)")
                        .font(.system(size: touch ? 14.5 : 12.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(asTypedTitle)
                        .font(.system(size: touch ? 13 : 12))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, touch ? 16 : 14)
                .frame(height: touch ? 44 : 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// What the line does as typed, such as "as typed: Switch to".
    private var asTypedTitle: String {
        guard let command = line.reading.primary else { return "as typed" }
        let title = CommandText.title(command, running: model.running, now: model.environment.now(), zone: model.environment.timeZone())
        return "as typed: \(title)"
    }

    /// On iPad and iPhone, what the line could also mean, such as logging
    /// it as done, as a row to tap, where the Mac has Option-Return.
    @ViewBuilder
    private var alternate: some View {
        if !line.text.isEmpty, line.recalledEntry == nil, let command = line.reading.alternate {
            Button {
                submit(true)
            } label: {
                HStack(spacing: 8) {
                    Text("Or:")
                        .foregroundStyle(Theme.text2)
                    Text(CommandText.title(command, running: model.running, now: model.environment.now(), zone: model.environment.timeZone()))
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { divider }
        }
    }

    // MARK: - Keys

    /// The keys that do something with what's typed.
    private var hints: some View {
        HStack(spacing: 16) {
            if line.text.isEmpty {
                KeyHint("↑", "earlier lines")
            } else if line.recalledEntry != nil {
                KeyHint("⏎", "start again")
                KeyHint("↑↓", "choose")
                KeyHint("⇥", "copy to the line")
            } else if !line.recalled.isEmpty {
                KeyHint("↑↓", "choose")
            } else if let completion = line.reading.completion {
                KeyHint("⇥", "\(completion.text), from \(Format.weekday(completion.day))")
                    .lineLimit(1)
            } else if case .addProject? = line.reading.alternate {
                KeyHint("⌥⏎", "add and start")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

/// A line colored as the command line's field colors it: the project
/// underlined in its color, tags in blue, times in amber and words such as
/// "stop" in the accent color.
struct ReadingText: View {
    let reading: CommandReading
    let ledger: Ledger

    var body: some View {
        text.foregroundStyle(Theme.text)
    }

    private var text: Text {
        let line = reading.text
        var result = Text(verbatim: "")
        var position = line.startIndex
        for token in reading.tokens where token.range.lowerBound >= position {
            if position < token.range.lowerBound {
                result = result + Text(verbatim: String(line[position..<token.range.lowerBound]))
            }
            result = result + styled(Text(verbatim: String(line[token.range])), token.kind)
            position = token.range.upperBound
        }
        if position < line.endIndex {
            result = result + Text(verbatim: String(line[position...]))
        }
        return result
    }

    private func styled(_ text: Text, _ kind: CommandToken.Kind) -> Text {
        switch kind {
        case let .project(id):
            text.underline(true, color: ledger.tint(ofProject: id).ink)
        case .client:
            text.underline(true, color: Theme.text2)
        case .tag:
            text.foregroundColor(Theme.tag)
        case .time:
            text.foregroundColor(Theme.amberText)
        case .keyword:
            text.foregroundColor(Theme.accent)
        case .name:
            text.fontWeight(.semibold)
        case let .color(hex):
            text.foregroundColor(ProjectTint(hex: hex).ink)
        case .note, .unknown:
            text
        }
    }
}

#if DEBUG
#Preview("Nothing Typed") {
    CommandDetails(line: CommandLineModel(model: PreviewData.model()), continuesField: false, submit: { _ in })
        .frame(width: 440)
        .background(Theme.panel)
}

#Preview("Earlier Entries") {
    let line = CommandLineModel(model: PreviewData.model())
    line.text = "web"
    return CommandDetails(line: line, continuesField: false, submit: { _ in })
        .frame(width: 440)
        .background(Theme.panel)
}

#Preview("Earlier Entries, Touch") {
    let line = CommandLineModel(model: PreviewData.model())
    line.text = "web"
    return CommandDetails(line: line, continuesField: false, size: .touch, submit: { _ in })
        .frame(width: 390)
        .background(Theme.panel)
}
#endif
