#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The timeline on iPad, as on the Mac: a day or a week of entries on an
/// hour grid, or a month as a calendar, with the selected entry in the
/// inspector.
struct PadTimelineScreen: View {
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

    /// What the inspector says to do with no entry selected. In the month's
    /// calendar a day's number opens the day, where a double-tap on the
    /// hour grid adds an entry.
    private var summaryHint: String {
        switch span {
        case .day, .week:
            "Tap an entry to edit it, and tap empty space to come back here. Double-tap empty space to add an entry."
        case .month:
            "Tap an entry to edit it, and tap empty space to come back here. Tap a day's number to see it on its own."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addEntry) {
                    Label("New Entry", systemImage: "plus")
                }
                .help(shownDay == model.today ? "Add an entry for the last hour" : "Add an entry at 9:00")
                .disabled(model.isReadOnly)
                PadInspectorButton(shown: $showInspector)
            }
        }
        .padInspector(shown: $showInspector, hasSelection: selection != nil) {
            selection = nil
        } inspector: {
            NavigationStack {
                if let id = selection, model.resolved.contains(where: { $0.id == id }) {
                    EntryForm(model: model, id: id, select: { copy in
                        selection = copy
                    }, deleted: {
                        selection = nil
                    })
                    .id(id)
                } else {
                    PeriodSummary(
                        title: title,
                        entries: model.resolved.filter { range.contains($0.entry.day) },
                        ledger: model.ledger,
                        now: model.now,
                        hint: summaryHint
                    )
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            EntriesSheetView(model: model, sheet: sheet)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch span {
        case .day:
            PadTimeGrid(model: model, days: [shownDay], selection: $selection, sheet: $sheet)
        case .week:
            PadTimeGrid(model: model, days: weekDays, selection: $selection, sheet: $sheet, openDay: show)
        case .month:
            PadMonthCalendar(model: model, month: shownDay, selection: $selection, sheet: $sheet, openDay: show)
        }
    }

    /// The days of the week shown.
    private var weekDays: [LocalDate] {
        let start = range.lowerBound
        return (0...6).map { start.adding(days: $0) }
    }

    // MARK: Header

    /// The period's title and moving through periods; in a narrow window
    /// on two lines.
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
        HStack(spacing: 6) {
            Button {
                step(by: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Show the previous \(span.rawValue)")
            Button("Today") {
                day = nil
            }
            .keyboardShortcut("t", modifiers: .command)
            .help("Show today")
            Button {
                step(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help("Show the next \(span.rawValue)")
        }
        .buttonStyle(.bordered)
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

    /// The time logged, which matters more than the words around it.
    private var totalText: some View {
        HStack(spacing: 4) {
            Text(Format.duration(total))
                .fontWeight(.semibold)
                .monospacedDigit()
            Text("logged")
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
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

    private var dayPicker: some View {
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
        .help("Show a day of your choice")
    }

    /// The time logged in the period shown.
    private var total: Int64 {
        let days = range
        return model.resolved
            .filter { days.contains($0.entry.day) }
            .reduce(0) { $0 + model.duration(of: $1) }
    }

    // MARK: Actions

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

    /// Adds an hour: the last one when the day shown is today, or from 9:00
    /// on another day.
    private func addEntry() {
        if shownDay == model.today {
            let end = model.environment.now().wholeSeconds
            let entry = TimeEntry(start: end.adding(seconds: -3600), end: end, timeZone: model.environment.timeZone(), updated: end)
            model.addEntry(entry, undoManager: undoManager)
            selection = entry.id
        } else if let id = model.addHour(on: shownDay, at: 9 * 3600, undoManager: undoManager) {
            selection = id
        }
    }
}

// MARK: - Hour grid

/// Days side by side on an hour grid, for the iPad: one for the day view,
/// seven for the week view. Each day's entries are blocks at their own
/// wall-clock time. Tap a block to select it; drag the selected block to
/// move it, in the week view to another day too, or its handles to change
/// its start or end; double-tap empty space to add an hour; touch and hold
/// a block for its menu. Times snap to five minutes.
struct PadTimeGrid: View {
    let model: AppModel
    let days: [LocalDate]
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    /// Shows one day, when a day's heading in the week view is tapped.
    var openDay: ((LocalDate) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var drag: DragState?

    /// The grid's coordinate space. Drags are measured in it rather than in
    /// the block's own, because the block moves under the finger while it's
    /// dragged.
    static let space = "PadTimeGrid"

    struct DragState: Equatable {
        var id: UUID
        var kind: HourGrid.DragKind
        var startSecond: Int
        var endSecond: Int
        /// How many days the block moves, in the week view.
        var dayShift: Int
    }

    var body: some View {
        let today = model.today
        let columns = days.map { DayLayout.blocks(on: $0, entries: model.resolved, now: model.now) }
        let flagged = model.overlaps.flagged
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Section {
                        grid(columns: columns, flagged: flagged, today: today)
                    } header: {
                        if days.count > 1 {
                            dayHeadings(columns: columns, today: today)
                        }
                    }
                }
            }
            .onAppear {
                scroll(proxy, to: HourGrid.firstHour(columns))
            }
            .onChange(of: days) { _, newDays in
                let blocks = newDays.map { DayLayout.blocks(on: $0, entries: model.resolved, now: model.now) }
                scroll(proxy, to: HourGrid.firstHour(blocks))
            }
        }
        // A tick for each five minutes a drag moves a time by.
        .sensoryFeedback(.selection, trigger: drag)
        .overlay(alignment: .bottom) {
            if columns.allSatisfy(\.isEmpty) {
                Text("Double-tap to add an entry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: Grid

    private func grid(columns: [[DayBlock]], flagged: Set<UUID>, today: LocalDate) -> some View {
        ZStack(alignment: .topLeading) {
            HourLines()
            GeometryReader { geometry in
                let dayWidth = HourGrid.dayWidth(geometry.size.width, days: days.count)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: dayWidth, height: HourGrid.hourHeight * 24)
                            .onTapGesture(count: 2) { location in
                                addEntry(on: day, atY: location.y)
                            }
                            .onTapGesture {
                                selection = nil
                            }
                            .offset(x: HourGrid.gutter + CGFloat(index) * dayWidth)
                    }
                    ForEach(1..<max(days.count, 1), id: \.self) { index in
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: HourGrid.hourHeight * 24)
                            .offset(x: HourGrid.gutter + CGFloat(index) * dayWidth)
                            .allowsHitTesting(false)
                    }
                    ForEach(Array(days.enumerated()), id: \.element) { index, _ in
                        ForEach(columns[index]) { block in
                            blockView(block, dayIndex: index, dayWidth: dayWidth, flagged: flagged.contains(block.id))
                        }
                    }
                    if let index = days.firstIndex(of: today) {
                        nowLine(dayIndex: index, dayWidth: dayWidth)
                    }
                }
            }
        }
        .frame(height: HourGrid.hourHeight * 24)
        .coordinateSpace(.named(Self.space))
        .padding(.vertical, 10)
    }

    /// The week view's headings: each day's weekday, date and total. Tap one
    /// to show that day.
    private func dayHeadings(columns: [[DayBlock]], today: LocalDate) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: HourGrid.gutter, height: 1)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let total = columns[index].reduce(Int64(0)) { $0 + model.duration(of: $1.entry) }
                Button {
                    openDay?(day)
                } label: {
                    WeekDayHeading(day: day, isToday: day == today, total: total)
                }
                .buttonStyle(.plain)
                .help("Show \(Format.longDay(day))")
            }
            Color.clear
                .frame(width: HourGrid.trailing, height: 1)
        }
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// The line at the time now, in the zone "today" is worked out in.
    private func nowLine(dayIndex: Int, dayWidth: CGFloat) -> some View {
        let second = model.now.local(in: model.environment.timeZone()).millisecondOfDay / 1000
        return NowLine(width: dayWidth)
            .offset(x: HourGrid.gutter + CGFloat(dayIndex) * dayWidth, y: HourGrid.y(second) - NowLine.radius)
    }

    /// Scrolls so `hour` is at the top. Scrolling while the grid is first
    /// laid out does nothing, so it waits for that to finish.
    private func scroll(_ proxy: ScrollViewProxy, to hour: Int) {
        Task {
            proxy.scrollTo(hour, anchor: .top)
        }
    }

    // MARK: Blocks

    private func blockView(_ block: DayBlock, dayIndex: Int, dayWidth: CGFloat, flagged: Bool) -> some View {
        let preview = drag.flatMap { $0.id == block.id ? $0 : nil }
        let startSecond = preview?.startSecond ?? block.startSecond
        let endSecond = preview?.endSecond ?? block.endSecond
        let shownDay = dayIndex + (preview?.dayShift ?? 0)
        let columnWidth = dayWidth / CGFloat(block.columns)
        let resolved = block.entry
        let selected = selection == block.id
        // Only the selected block moves, so a swipe across the others
        // scrolls.
        let editable = selected && !model.isReadOnly
        return TimelineBlock(
            title: model.ledger.projectTitle(resolved.entry.projectID),
            detail: TimelineBlock.detail(resolved, startSecond: startSecond, endSecond: endSecond, dragging: preview != nil),
            tags: resolved.entry.tags,
            links: model.ledger.issueLinks(tags: resolved.entry.tags, projectID: resolved.entry.projectID),
            color: model.ledger.color(ofProject: resolved.entry.projectID),
            flagged: flagged,
            selected: selected,
            running: resolved.isRunning
        )
        .frame(width: max(columnWidth - 3, 8), height: max(HourGrid.y(endSecond) - HourGrid.y(startSecond) - 2, 12))
        .overlay(alignment: .top) {
            if editable {
                GrabHandle(edge: .top)
                    .offset(y: -GrabHandle.outside)
                    .gesture(dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .start))
            }
        }
        .overlay(alignment: .bottom) {
            if editable, !resolved.isRunning {
                GrabHandle(edge: .bottom)
                    .offset(y: GrabHandle.outside)
                    .gesture(dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .end))
            }
        }
        .gesture(
            dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .move),
            including: editable && !resolved.isRunning ? .all : .subviews
        )
        .onTapGesture {
            selection = block.id
        }
        .contextMenu {
            EntriesMenu(model: model, ids: [block.id], undoManager: undoManager, sheet: $sheet) { copies in
                selection = copies.first
            }
        }
        .zIndex(selected ? 1 : 0)
        .offset(x: HourGrid.gutter + CGFloat(shownDay) * dayWidth + CGFloat(block.column) * columnWidth, y: HourGrid.y(startSecond))
    }

    // MARK: Editing

    private func dragGesture(_ block: DayBlock, dayIndex: Int, dayWidth: CGFloat, kind: HourGrid.DragKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !model.isReadOnly, kind != .move || !block.entry.isRunning else { return }
                let delta = Int((value.translation.height / HourGrid.hourHeight * 3600).rounded())
                let (start, end) = HourGrid.adjusted(block, kind: kind, by: delta)
                let shift = kind == .move
                    ? HourGrid.dayShift(value.translation.width, dayWidth: dayWidth, from: dayIndex, days: days.count)
                    : 0
                drag = DragState(id: block.id, kind: kind, startSecond: start, endSecond: end, dayShift: shift)
            }
            .onEnded { _ in
                if let drag, drag.id == block.id, days.indices.contains(dayIndex) {
                    model.applyDrag(
                        drag.kind,
                        to: block,
                        on: days[dayIndex],
                        startSecond: drag.startSecond,
                        endSecond: drag.endSecond,
                        dayShift: drag.dayShift,
                        undoManager: undoManager
                    )
                }
                drag = nil
            }
    }

    private func addEntry(on day: LocalDate, atY y: CGFloat) {
        if let id = model.addHour(on: day, at: HourGrid.newEntrySecond(atY: y), undoManager: undoManager) {
            selection = id
        }
    }
}

/// A round handle on the selected block's top or bottom edge, which drags
/// its start or end. What a finger can touch reaches mostly past the edge,
/// so a short block can still be moved by its middle.
struct GrabHandle: View {
    let edge: VerticalEdge

    /// How far the handle's touch area reaches past the block's edge.
    static let outside: CGFloat = 18
    static let height: CGFloat = 26

    var body: some View {
        Circle()
            .fill(Color(uiColor: .systemBackground))
            .overlay {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
            .frame(width: 11, height: 11)
            // On the edge, which isn't the touch area's middle.
            .offset(y: (edge == .top ? 1 : -1) * (Self.outside - Self.height / 2))
            .frame(width: 48, height: Self.height)
            .contentShape(Rectangle())
            .accessibilityLabel(edge == .top ? "Start" : "End")
    }
}

// MARK: - Month

/// A month as a calendar on iPad: a row for each week, each day with its
/// total and its entries. Tap an entry to select it; tap a day's number,
/// or its "more", to show the day on the timeline.
struct PadMonthCalendar: View {
    let model: AppModel
    /// Any day in the month shown.
    let month: LocalDate
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    let openDay: (LocalDate) -> Void

    var body: some View {
        let weeks = MonthGrid.weeks(of: month, firstWeekday: model.firstWeekday)
        let monthDays = ReportPeriod.month.range(containing: month, firstWeekday: model.firstWeekday)
        let shown = (weeks.first?.first ?? month)...(weeks.last?.last ?? month)
        let byDay = Dictionary(grouping: model.resolved.filter { shown.contains($0.entry.day) }) { $0.entry.day }
        let today = model.today
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weeks.first ?? [], id: \.self) { day in
                    Text(Format.weekday(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            Divider()
            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(max(weeks.count, 1))
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                PadMonthDayCell(
                                    model: model,
                                    day: day,
                                    entries: byDay[day] ?? [],
                                    inMonth: monthDays.contains(day),
                                    isToday: day == today,
                                    height: rowHeight,
                                    selection: $selection,
                                    sheet: $sheet,
                                    openDay: openDay
                                )
                                if day != week.last {
                                    Divider()
                                }
                            }
                        }
                        .frame(height: rowHeight - 1)
                        Divider()
                    }
                }
            }
        }
    }
}

/// A day in the iPad's month calendar: its number, its total, and as many
/// of its entries as fit.
struct PadMonthDayCell: View {
    let model: AppModel
    let day: LocalDate
    /// The day's entries, by start.
    let entries: [ResolvedEntry]
    let inMonth: Bool
    let isToday: Bool
    let height: CGFloat
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    let openDay: (LocalDate) -> Void
    @Environment(\.undoManager) private var undoManager
    /// The height of an entry's line, and of the day's number above the
    /// lines, which grow with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .callout) private var headerHeight: CGFloat = 34

    var body: some View {
        let total = entries.reduce(Int64(0)) { $0 + model.duration(of: $1) }
        let flagged = model.overlaps.flagged
        // The lines under the day's number, one of them for "more" when not
        // every entry fits.
        let lines = max(0, Int((height - headerHeight) / lineHeight))
        let shownCount = entries.count > lines ? max(lines - 1, 0) : entries.count
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    openDay(day)
                } label: {
                    DayNumber(day, font: .callout, isToday: isToday, dimmed: !inMonth)
                        .padding(.vertical, 1)
                }
                .buttonStyle(.plain)
                .help("Show \(Format.longDay(day))")
                Spacer(minLength: 2)
                if total > 0 {
                    Text(Format.duration(total))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 3)
            ForEach(entries.prefix(shownCount)) { entry in
                MonthEntryRow(
                    model: model,
                    entry: entry,
                    flagged: flagged.contains(entry.id),
                    selected: selection == entry.id,
                    height: lineHeight
                )
                .onTapGesture {
                    selection = entry.id
                }
                .contextMenu {
                    EntriesMenu(model: model, ids: [entry.id], undoManager: undoManager, sheet: $sheet) { copies in
                        selection = copies.first
                    }
                }
            }
            if shownCount < entries.count {
                Button("\(entries.count - shownCount) more") {
                    openDay(day)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .help("Show \(Format.longDay(day))")
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openDay(day)
        }
        // Back to the inspector's summary of the month, as on the Mac.
        .onTapGesture {
            selection = nil
        }
    }
}

#if DEBUG
#Preview("Day") {
    NavigationStack {
        PadTimelineScreen(model: PreviewData.model(), span: .day, selection: PreviewData.entry("Landing page copy"))
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTimelinePreview.day")!)
}

#Preview("Day, Overlap Selected") {
    NavigationStack {
        PadTimelineScreen(
            model: PreviewData.model(),
            span: .day,
            day: LocalDate(year: 2026, month: 9, day: 22),
            selection: PreviewData.entry("Call with Globex")
        )
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTimelinePreview.overlap")!)
}

#Preview("Week") {
    NavigationStack {
        PadTimelineScreen(model: PreviewData.model(), span: .week)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTimelinePreview.week")!)
}

#Preview("Month") {
    NavigationStack {
        PadTimelineScreen(model: PreviewData.model(), span: .month)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTimelinePreview.month")!)
}
#endif
#endif
