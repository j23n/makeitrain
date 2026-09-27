#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// How much of the calendar the timeline shows.
enum TimelineSpan: String, CaseIterable, Identifiable {
    case day, week, month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// The timeline: a day or a week of entries on an hour grid, or a month as
/// a calendar, with an inspector for the selected entry.
struct TimelineScreen: View {
    let model: AppModel
    /// A day in the period shown, or nil for today.
    @State private var day: LocalDate?
    @State private var selection: UUID?
    @State private var sheet: EntriesSheet?
    @AppStorage("timeline.span") private var span = TimelineSpan.day
    @AppStorage("timeline.inspector") private var showInspector = true
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, span: TimelineSpan = .day, day: LocalDate? = nil, selection: UUID? = nil) {
        self.model = model
        _span = AppStorage(wrappedValue: span, "timeline.span")
        _day = State(initialValue: day)
        _selection = State(initialValue: selection)
    }

    private var shownDay: LocalDate { day ?? model.today }

    /// The days of the period shown.
    private var range: ClosedRange<LocalDate> {
        switch span {
        case .day: shownDay...shownDay
        case .week: ReportPeriod.week.range(containing: shownDay, firstWeekday: model.firstWeekday)
        case .month: ReportPeriod.month.range(containing: shownDay, firstWeekday: model.firstWeekday)
        }
    }

    /// The days of the week shown.
    private var weekDays: [LocalDate] {
        let start = range.lowerBound
        return (0...6).map { start.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            EntryInspector(model: model, id: selection) { copy in
                selection = copy
            }
        }
        .sheet(item: $sheet) { sheet in
            EntriesSheetView(model: model, sheet: sheet, undoManager: undoManager)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch span {
        case .day:
            TimeGrid(model: model, days: [shownDay], selection: $selection, sheet: $sheet)
        case .week:
            TimeGrid(model: model, days: weekDays, selection: $selection, sheet: $sheet, openDay: show)
        case .month:
            MonthCalendar(model: model, month: shownDay, selection: $selection, sheet: $sheet, openDay: show)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ControlGroup {
                Button {
                    step(by: -1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .help("Show the previous \(span.rawValue)")
                Button("Today") {
                    day = nil
                }
                Button {
                    step(by: 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .help("Show the next \(span.rawValue)")
            }
            .fixedSize()
            Text(title)
                .font(.headline)
            Spacer()
            Picker("View", selection: $span) {
                ForEach(TimelineSpan.allCases) { span in
                    Text(span.title).tag(span)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("\(Format.duration(total)) logged")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            DatePicker(
                "Day",
                selection: Binding(
                    get: { shownDay.pickerDate },
                    set: { date in go(to: LocalDate(pickerDate: date)) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch span {
        case .day, .week: Format.days(range)
        case .month: Format.month(shownDay)
        }
    }

    /// The time logged in the period shown.
    private var total: Int64 {
        let days = range
        return model.resolved
            .filter { days.contains($0.entry.day) }
            .reduce(0) { $0 + model.duration(of: $1) }
    }

    /// Moves to the previous or next day, week or month.
    private func step(by steps: Int) {
        switch span {
        case .day:
            go(to: shownDay.adding(days: steps))
        case .week:
            go(to: shownDay.adding(days: 7 * steps))
        case .month:
            // The same day of the month, or the month's last day if it's shorter.
            let month = ReportPeriod.month.shift(range, by: steps, firstWeekday: model.firstWeekday)
            go(to: LocalDate(year: month.lowerBound.year, month: month.lowerBound.month, day: min(shownDay.day, month.upperBound.day)))
        }
    }

    private func go(to date: LocalDate) {
        day = date == model.today ? nil : date
    }

    /// Shows one day on the day timeline.
    private func show(_ date: LocalDate) {
        span = .day
        go(to: date)
    }
}

#if DEBUG
#Preview("Day") {
    TimelineScreen(model: PreviewData.model(), span: .day)
        .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.day")!)
        .frame(width: 1100, height: 700)
}

#Preview("Day, Overlap Selected") {
    TimelineScreen(
        model: PreviewData.model(),
        span: .day,
        day: LocalDate(year: 2026, month: 9, day: 22),
        selection: PreviewData.entry("Call with Globex")
    )
    .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.overlap")!)
    .frame(width: 1100, height: 700)
}

#Preview("Day in New York") {
    TimelineScreen(model: PreviewData.model(), span: .day, day: LocalDate(year: 2026, month: 9, day: 18))
        .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.newYork")!)
        .frame(width: 1100, height: 700)
}

#Preview("Week") {
    TimelineScreen(model: PreviewData.model(), span: .week)
        .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.week")!)
        .frame(width: 1200, height: 700)
}

#Preview("Month") {
    TimelineScreen(model: PreviewData.model(), span: .month)
        .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.month")!)
        .frame(width: 1200, height: 760)
}
#endif
#endif
