import SwiftUI
import TrackerCore
#if os(macOS)
import AppKit
#endif
import TrackerKit

/// A month as a report: what it covers as a sentence, the year's weeks,
/// the days of the month with their time, and the statement beside them.
/// Days can be chosen for another range by clicking and Shift-clicking
/// them, or with the arrow keys.
struct MonthScreen: View {
    let model: AppModel
    let navigator: Navigator
    let anchor: LocalDate
    @State private var state: ReportState
    @Environment(\.commandSidebarShown) private var commandSidebarShown
    @State private var cursor: LocalDate
    @FocusState private var focused: Bool

    init(model: AppModel, navigator: Navigator, anchor: LocalDate) {
        self.model = model
        self.navigator = navigator
        self.anchor = anchor
        let range = ReportPeriod.month.range(containing: anchor, firstWeekday: model.firstWeekday)
        _state = State(initialValue: ReportState(model: model, range: range, period: .month))
        _cursor = State(initialValue: anchor)
    }

    var body: some View {
        VStack(spacing: 0) {
            QueryBar(model: model, state: state)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        YearRibbon(model: model, state: state)
                        rangeLine
                        MonthHeatGrid(model: model, state: state, month: shownMonth, cursor: $cursor) { day in
                            navigator.go(.day(day))
                        }
                        keyHints
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
                if !commandSidebarShown {
                    StatementPanel(model: model, state: state, navigator: navigator)
                        .frame(width: 400)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard !isEditingText() else { return .ignored }
            let step = switch press.key {
            case .leftArrow: -1
            case .rightArrow: 1
            case .upArrow: -7
            default: 7
            }
            let next = cursor.adding(days: step)
            if press.modifiers.contains(.shift) {
                let anchor = state.range.lowerBound == cursor ? state.range.upperBound : state.range.lowerBound
                state.show(min(anchor, next)...max(anchor, next), period: .custom)
            } else {
                state.show(next...next, period: .day)
            }
            cursor = next
            return .handled
        }
        .onKeyPress(.return) {
            guard !isEditingText() else { return .ignored }
            navigator.go(.day(cursor))
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "wW")) { _ in
            guard !isEditingText() else { return .ignored }
            navigator.go(.week(cursor))
            return .handled
        }
        .onChange(of: anchor) { _, day in
            state.show(ReportPeriod.month.range(containing: day, firstWeekday: model.firstWeekday), period: .month)
            cursor = day
        }
        .onChange(of: model.revision) {
            state.refresh()
        }
        .onAppear {
            focused = true
        }
    }

    /// The month the grid shows: the range's, or its last's for a range
    /// over several months.
    private var shownMonth: LocalDate {
        state.range.upperBound.monthKey == state.range.lowerBound.monthKey ? state.range.lowerBound : cursor
    }

    private var rangeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(Format.days(state.range))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            legend
        }
    }

    private var legend: some View {
        let projects = Set(state.report.entries.compactMap(\.entry.projectID))
        let shown = projects.sorted { model.ledger.projectTitle($0) < model.ledger.projectTitle($1) }.prefix(3)
        let filteredOut = model.ledger.pickerProjects().filter { !projects.contains($0.id) }.count
        return HStack(spacing: 12) {
            ForEach(Array(shown), id: \.self) { projectID in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(model.ledger.tint(ofProject: projectID).bar).frame(width: 8, height: 8)
                    Text(model.ledger.projects[projectID]?.name ?? "")
                }
            }
            if !state.overlapDaysInRange.isEmpty {
                HStack(spacing: 5) {
                    OverlapSwatch(size: 10)
                    Text("overlap")
                }
            }
            if !state.clients.isEmpty || !state.projects.isEmpty, filteredOut > 0 {
                Text("\(filteredOut) \(filteredOut == 1 ? "project" : "projects") filtered out")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
    }

    private var keyHints: some View {
        HStack(spacing: 18) {
            KeyHint("← → ↑ ↓", "move")
            KeyHint("⇧", "extend")
            KeyHint("⏎", "open day")
            KeyHint("W", "open week")
        }
    }
}

/// A month's days in weeks: each with its date, its time, a bar of its
/// time by project, and a mark where entries overlap. Days in the range
/// are outlined.
struct MonthHeatGrid: View {
    let model: AppModel
    let state: ReportState
    let month: LocalDate
    @Binding var cursor: LocalDate
    let open: (LocalDate) -> Void
    @State private var dragStart: LocalDate?

    var body: some View {
        let weeks = MonthGrid.weeks(of: month, firstWeekday: model.firstWeekday)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(weeks.first ?? [], id: \.self) { day in
                    Text(Format.weekday(day))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                        .padding(.leading, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { day in
                        cell(day)
                    }
                }
            }
        }
    }

    private func cell(_ day: LocalDate) -> some View {
        let total = state.dayTotals[day] ?? 0
        let inMonth = day.month == month.month && day.year == month.year
        let weekend = day.weekday == 1 || day.weekday == 7
        let selected = state.range.contains(day)
        let projects = (state.dayProjects[day] ?? [:]).sorted { ($0.value, $0.key?.uuidString ?? "") > ($1.value, $1.key?.uuidString ?? "") }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(day.day)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(day == model.today ? Theme.accent : (weekend ? Theme.text2 : Theme.text))
                Spacer(minLength: 2)
                if state.overlapDays.contains(day) {
                    OverlapSwatch(size: 10)
                        .accessibilityLabel(Text("Overlap"))
                }
                Text(total > 0 ? Format.duration(total) : "—")
                    .font(.system(size: 11, weight: total > Corrections.longest ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(total > Corrections.longest ? Theme.amberText : (total > 0 ? Theme.text4 : Theme.text3))
            }
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                ForEach(projects, id: \.key) { item in
                    Rectangle()
                        .fill(model.ledger.tint(ofProject: item.key).bar)
                        .frame(height: max(1, CGFloat(min(item.value, ChartScale.fullDay)) / CGFloat(ChartScale.fullDay) * 64))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .background(RoundedRectangle(cornerRadius: 8).fill(inMonth ? (weekend ? Theme.weekendCell : Theme.cell) : Theme.outsideCell))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Theme.accent : (day == cursor ? Theme.accentLine : Theme.line), lineWidth: selected ? 1.5 : 1)
        }
        .opacity(inMonth ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            open(day)
        }
        .onTapGesture {
            if extendsSelection {
                let anchor = state.range.lowerBound
                state.show(min(anchor, day)...max(anchor, day), period: .custom)
            } else {
                state.show(day...day, period: .day)
            }
            cursor = day
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Format.longDay(day)), \(total > 0 ? Format.duration(total) : "no time")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Whether Shift is held, so a click stretches the range to the day.
    /// On iPad, Shift and the arrows do it instead.
    private var extendsSelection: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.shift)
        #else
        return false
        #endif
    }
}

/// A year as a report: the weeks, a small month for each month, and the
/// statement for the year.
struct YearScreen: View {
    let model: AppModel
    let navigator: Navigator
    let year: Int
    @State private var state: ReportState
    @Environment(\.commandSidebarShown) private var commandSidebarShown

    init(model: AppModel, navigator: Navigator, year: Int) {
        self.model = model
        self.navigator = navigator
        self.year = year
        _state = State(initialValue: ReportState(model: model, range: Self.range(year), period: .custom))
    }

    static func range(_ year: Int) -> ClosedRange<LocalDate> {
        LocalDate(year: year, month: 1, day: 1)...LocalDate(year: year, month: 12, day: 31)
    }

    var body: some View {
        VStack(spacing: 0) {
            QueryBar(model: model, state: state)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        YearRibbon(model: model, state: state)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                            ForEach(1...12, id: \.self) { month in
                                MiniMonth(model: model, state: state, month: LocalDate(year: state.range.lowerBound.year, month: month, day: 1)) {
                                    navigator.go(.month(LocalDate(year: state.range.lowerBound.year, month: month, day: 1)))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
                if !commandSidebarShown {
                    StatementPanel(model: model, state: state, navigator: navigator)
                        .frame(width: 400)
                }
            }
        }
        .onChange(of: year) { _, year in
            state.show(Self.range(year), period: .custom)
        }
        .onChange(of: model.revision) {
            state.refresh()
        }
    }
}

/// A month's days as small squares, darker for more time, with its total.
struct MiniMonth: View {
    let model: AppModel
    let state: ReportState
    let month: LocalDate
    let open: () -> Void

    var body: some View {
        let weeks = MonthGrid.weeks(of: month, firstWeekday: model.firstWeekday)
        let total = state.months.first { $0.month == month.month }?.total ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.month(month))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(total > 0 ? Format.duration(total) : "—")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            VStack(spacing: 3) {
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 3) {
                        ForEach(week, id: \.self) { day in
                            let time = state.dayTotals[day] ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.month == month.month ? shade(time) : Color.clear)
                                .overlay {
                                    if state.overlapDays.contains(day), day.month == month.month {
                                        RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.amber, lineWidth: 1)
                                    }
                                }
                                .frame(height: 16)
                                .help("\(Format.longDay(day)), \(time > 0 ? Format.duration(time) : "no time")")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Format.month(month)), \(total > 0 ? Format.duration(total) : "no time")"))
        .accessibilityAddTraits(.isButton)
    }

    private func shade(_ time: Int64) -> Color {
        guard time > 0 else { return Theme.emptyBar }
        let level = min(Double(time) / (9 * 3_600_000), 1)
        return Theme.accent.opacity(0.18 + level * 0.67)
    }
}
