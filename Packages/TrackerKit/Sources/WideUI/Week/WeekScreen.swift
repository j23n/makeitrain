import SwiftUI
import TrackerCore
import TrackerKit

/// One day or a week of entries.
enum WeekSpan {
    case day, week
}

/// What the week's sidebar shows.
private enum WeekSide: Equatable {
    case entry(UUID)
    case corrections
}

/// A week, or a day, on an hour grid, with what needs correcting shown in
/// place, and beside it the selected entry or, when there's no selection,
/// what needs correcting.
struct WeekScreen: View {
    let model: AppModel
    let navigator: Navigator
    let anchor: LocalDate
    let span: WeekSpan
    @State private var week: WeekModel
    @FocusState private var focused: Bool
    /// Changes when Return should put the keyboard in the selected entry's
    /// line.
    @State private var lineFocusRequest = 0
    @Environment(\.undoManager) private var undoManager
    @Environment(\.commandSidebarShown) private var commandSidebarShown

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

    /// What the sidebar shows: the selected entry, or else what needs
    /// correcting when anything does. Nothing while the command line has it.
    private var side: WeekSide? {
        guard !commandSidebarShown else { return nil }
        if let id = week.selectedEntry, model.ledger.entries[id].map({ !$0.isDeleted }) == true {
            return .entry(id)
        }
        return week.previews.isEmpty ? nil : .corrections
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                WeekCanvas(model: model, week: week, days: shownDays) {
                    focused = true
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            switch side {
            case let .entry(id)?:
                EntryPanel(model: model, entryID: id, focusRequest: lineFocusRequest) { copy in
                    week.selectedEntry = copy
                } close: {
                    week.selectedEntry = nil
                    focused = true
                }
                .transition(.move(edge: .trailing))
            case .corrections?:
                CorrectionsPanel(model: model, week: week)
                    .transition(.move(edge: .trailing))
            case nil:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.15), value: side)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: ["j", "k"]) { press in
            guard !isEditingText() else { return .ignored }
            week.selectedEntry = nil
            week.moveSelection(by: press.key == "j" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isEditingText() else { return .ignored }
            switch side {
            case .entry?:
                lineFocusRequest += 1
            case .corrections?:
                week.acceptSelected(undoManager: undoManager)
            case nil:
                return .ignored
            }
            return .handled
        }
        .onKeyPress(.tab) {
            guard !isEditingText(), side == .corrections else { return .ignored }
            week.skipSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            guard !isEditingText(), week.selectedEntry != nil else { return .ignored }
            week.selectedEntry = nil
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
            week.refresh()
        }
        .onChange(of: navigator.entryToSelect, initial: true) { _, id in
            guard let id else { return }
            week.selectedEntry = id
            navigator.entryToSelect = nil
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
