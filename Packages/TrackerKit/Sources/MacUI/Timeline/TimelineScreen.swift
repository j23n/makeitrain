#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

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
        span.range(around: shownDay, firstWeekday: model.firstWeekday)
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
            EntryInspector(model: model, id: selection, days: range, title: title) { copy in
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

    /// The period's title and moving through periods, as on iPad; in a
    /// narrow window, such as beside the inspector, on two lines.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                navigation
                titleText
                Spacer(minLength: 8)
                totalText
                spanPicker
                dayPicker
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    navigation
                    titleText
                    Spacer(minLength: 8)
                    totalText
                }
                HStack(spacing: 12) {
                    spanPicker
                    Spacer(minLength: 8)
                    dayPicker
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var navigation: some View {
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
            .help("Show today")
            Button {
                step(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .help("Show the next \(span.rawValue)")
        }
        .fixedSize()
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
    }

    private var title: String {
        switch span {
        case .day, .week: Format.days(range)
        case .month: Format.month(shownDay)
        }
    }

    private var totalText: some View {
        Text("\(Format.duration(total)) logged")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var spanPicker: some View {
        Picker("View", selection: $span) {
            ForEach(TimelineSpan.allCases) { span in
                Text(span.title).tag(span)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Show a day, a week or a month")
    }

    /// A field without a stepper, like the entries' dates; clicking it
    /// opens a calendar.
    private var dayPicker: some View {
        DatePicker(
            "Day",
            selection: Binding(
                get: { shownDay.pickerDate },
                set: { date in go(to: LocalDate(pickerDate: date)) }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .fixedSize()
        .help("Show a day of your choice")
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
        go(to: span.day(shownDay, movedBy: steps, firstWeekday: model.firstWeekday))
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

#Preview("Week, Narrow") {
    TimelineScreen(model: PreviewData.model(), span: .week)
        .defaultAppStorage(UserDefaults(suiteName: "TimelinePreview.narrow")!)
        .frame(width: 720, height: 700)
}
#endif
#endif
