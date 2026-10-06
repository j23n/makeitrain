import SwiftUI
import TrackerCore
import TrackerKit

/// One day or a week of entries.
enum WeekSpan {
    case day, week
}

/// A week, or a day, on an hour grid, with what needs correcting shown in
/// place and listed beside it, and the selected entry as a line to edit.
struct WeekScreen: View {
    let model: AppModel
    let navigator: Navigator
    let anchor: LocalDate
    let span: WeekSpan
    @State private var week: WeekModel
    @FocusState private var focused: Bool
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, navigator: Navigator, anchor: LocalDate, span: WeekSpan) {
        self.model = model
        self.navigator = navigator
        self.anchor = anchor
        self.span = span
        _week = State(initialValue: WeekModel(model: model, days: Self.range(anchor, span, model.firstWeekday)))
    }

    static func range(_ anchor: LocalDate, _ span: WeekSpan, _ firstWeekday: Int) -> ClosedRange<LocalDate> {
        span == .day ? anchor...anchor : ReportPeriod.week.range(containing: anchor, firstWeekday: firstWeekday)
    }

    private var range: ClosedRange<LocalDate> {
        Self.range(anchor, span, model.firstWeekday)
    }

    /// The days shown: the week's, leaving out a weekend day with nothing
    /// on it.
    private var shownDays: [LocalDate] {
        var days: [LocalDate] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            days.append(day)
            day = day.adding(days: 1)
        }
        guard span == .week else { return days }
        let corrected = Set(week.corrections.map(\.day))
        return days.filter { day in
            let weekend = day.weekday == 1 || day.weekday == 7
            return !weekend || !week.entries(on: day).isEmpty || corrected.contains(day) || day == model.today
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                WeekCanvas(model: model, week: week, days: shownDays) {
                    focused = true
                }
                LineEditor(model: model, entryID: week.selectedEntry)
            }
            .padding(.top, 18)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            CorrectionsPanel(model: model, week: week)
                .frame(width: 380)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: ["j", "k"]) { press in
            guard !isEditingText() else { return .ignored }
            week.moveSelection(by: press.key == "j" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isEditingText() else { return .ignored }
            week.acceptSelected(undoManager: undoManager)
            return .handled
        }
        .onKeyPress(.tab) {
            guard !isEditingText() else { return .ignored }
            week.skipSelected()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isEditingText() else { return .ignored }
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isEditingText() else { return .ignored }
            step(1)
            return .handled
        }
        .onChange(of: range) { _, days in
            week.show(days)
        }
        .onChange(of: model.revision) {
            week.refresh()
        }
        .onChange(of: model.preferences.skippedCorrections) {
            week.refresh(force: true)
        }
        .onAppear {
            focused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Format.days(range))
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 2) {
                stepButton("chevron.left", span == .day ? "Previous day" : "Previous week", -1)
                stepButton("chevron.right", span == .day ? "Next day" : "Next week", 1)
            }
            if !range.contains(model.today) {
                Button("Today") {
                    navigator.replace(span == .day ? .day(model.today) : .week(model.today))
                }
                .buttonStyle(ChoiceButtonStyle(compact: true))
            }
            legend
            Spacer(minLength: 12)
            totals
        }
    }

    private func stepButton(_ systemImage: String, _ title: String, _ direction: Int) -> some View {
        Button {
            step(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func step(_ direction: Int) {
        let day = anchor.adding(days: (span == .day ? 1 : 7) * direction)
        navigator.replace(span == .day ? .day(day) : .week(day))
    }

    /// The projects on the days shown, and what the dashed blocks mean.
    private var legend: some View {
        let days = shownDays
        var projects: [UUID?: Int64] = [:]
        for day in days {
            for (projectID, time) in model.dayTotals.projects(on: day, now: model.now) {
                projects[projectID, default: 0] += time
            }
        }
        let shown = projects.keys.compactMap { $0 }.sorted { (projects[$0] ?? 0) > (projects[$1] ?? 0) }.prefix(4)
        let dashed = week.corrections.contains { correction in
            switch correction.kind {
            case .noProject, .notLogged: true
            default: false
            }
        }
        let hidesWeekend = span == .week && days.count < 7
        return HStack(spacing: 12) {
            ForEach(Array(shown), id: \.self) { projectID in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(model.ledger.tint(ofProject: projectID).ink)
                        .frame(width: 8, height: 8)
                    Text(model.ledger.projects[projectID]?.name ?? "")
                }
            }
            if dashed {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.ghost, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 9, height: 9)
                    Text("not logged or no project")
                }
            }
            if hidesWeekend {
                Text("Weekend hidden: nothing logged")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
        .lineLimit(1)
    }

    /// The days' total, and what it would be with the corrections.
    @ViewBuilder
    private var totals: some View {
        let totals = week.totals
        if let corrected = totals.corrected {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.duration(totals.total))
                    .font(.system(size: 13.5))
                    .strikethrough(true, color: Theme.amber)
                    .foregroundStyle(Theme.text3)
                Text(Format.duration(corrected))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                Text("with corrections")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            }
            .monospacedDigit()
            .fixedSize()
        } else {
            Text(Format.duration(totals.total))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .fixedSize()
        }
    }
}

/// The selected entry as a line, to change it by typing: Return applies
/// the line, Escape puts it back. While it's edited, what could replace the
/// word being typed shows under it, and what the line reads as.
struct LineEditor: View {
    let model: AppModel
    let entryID: UUID?
    @State private var line: EntryLineModel
    @State private var editing = false
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, entryID: UUID?) {
        self.model = model
        self.entryID = entryID
        _line = State(initialValue: EntryLineModel(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Text("Selected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 52, alignment: .leading)
                if let entry = line.entry {
                    HStack(spacing: 10) {
                        CommandField(
                            text: Binding(get: { line.text }, set: { line.text = $0 }),
                            placeholder: "",
                            reading: model.read(line.text),
                            ledger: model.ledger,
                            fontSize: 13.5,
                            cursorRequest: line.cursorRequest,
                            cursor: line.requestedCursor,
                            onSubmit: { _ in
                                if line.apply(undoManager: undoManager) {
                                    line.revert()
                                }
                            },
                            onTab: { line.acceptSuggestion() },
                            onUp: { line.moveSuggestion(by: -1) },
                            onDown: { line.moveSuggestion(by: 1) },
                            onCancel: { line.revert() },
                            onCursorChange: { line.cursor = $0 },
                            onFocusChange: { editing = $0 }
                        )
                        .frame(height: 22)
                        Text(Format.duration(model.duration(of: entry)))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(line.refused ? Theme.amber : editing ? Theme.accent : Theme.strongLine, lineWidth: editing || line.refused ? 1.5 : 1))
                    HStack(spacing: 6) {
                        KeyCap("⏎")
                        Text("apply")
                        KeyCap("esc")
                        Text("revert")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .fixedSize()
                } else {
                    Text("Select an entry to edit it here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }
            }
            if line.entry != nil, editing || line.refused {
                VStack(alignment: .leading, spacing: 8) {
                    // The row stays while suggestions come and go, so the
                    // line above doesn't move.
                    Color.clear
                        .frame(height: 24)
                        .overlay(alignment: .leading) {
                            if !line.suggestions.isEmpty {
                                SuggestionStrip(suggestions: line.suggestions, highlighted: line.highlightedSuggestion, ledger: model.ledger) { index in
                                    line.acceptSuggestion(at: index)
                                }
                            }
                        }
                    EntryLineGuide(model: model, line: line)
                }
                .padding(.leading, 66)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        .onChange(of: entryID, initial: true) {
            line.show(entryID)
        }
        .onChange(of: model.revision) {
            if !editing {
                line.revert()
            }
        }
    }
}
