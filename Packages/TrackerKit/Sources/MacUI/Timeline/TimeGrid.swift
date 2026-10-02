#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// Days side by side on an hour grid: one for the day view, seven for the
/// week view. Each day's entries are blocks at their own wall-clock time.
/// Drag a block to move it, in the week view to another day too; drag its
/// top or bottom edge to change its start or end; double-click empty space
/// to add an hour. Times snap to five minutes.
struct TimeGrid: View {
    let model: AppModel
    let days: [LocalDate]
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    /// Shows one day, when a day's heading in the week view is clicked.
    var openDay: ((LocalDate) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var drag: DragState?

    /// The grid's coordinate space. Drags are measured in it rather than in
    /// the block's own, because the block moves under the pointer while
    /// it's dragged.
    static let space = "TimeGrid"

    struct DragState {
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
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand {
            guard let selection, !model.isReadOnly else { return }
            model.deleteEntries([selection], undoManager: undoManager)
        }
        .overlay(alignment: .bottom) {
            if columns.allSatisfy(\.isEmpty) {
                Text("Double-click to add an entry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: Grid

    private func grid(columns: [[DayBlock]], flagged: Set<UUID>, today: LocalDate) -> some View {
        ZStack(alignment: .topLeading) {
            hourLines
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

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(Format.hour(hour))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: HourGrid.gutter - 10, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Divider()
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: HourGrid.hourHeight)
                .id(hour)
            }
        }
    }

    /// The week view's headings: each day's weekday, date and total. Click
    /// one to show that day.
    private func dayHeadings(columns: [[DayBlock]], today: LocalDate) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: HourGrid.gutter, height: 1)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let total = columns[index].reduce(Int64(0)) { $0 + model.duration(of: $1.entry) }
                Button {
                    openDay?(day)
                } label: {
                    VStack(spacing: 1) {
                        Text(Format.weekday(day))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(day.day)")
                            .font(.title3.weight(day == today ? .semibold : .regular))
                            .foregroundStyle(day == today ? Color.accentColor : Color.primary)
                        Text(total > 0 ? Format.duration(total) : " ")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
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

    private func nowLine(dayIndex: Int, dayWidth: CGFloat) -> some View {
        let second = model.now.local(in: TimeZone.current.identifier).millisecondOfDay / 1000
        return Rectangle()
            .fill(Color.red)
            .frame(width: dayWidth, height: 1.5)
            .offset(x: HourGrid.gutter + CGFloat(dayIndex) * dayWidth, y: y(second))
            .allowsHitTesting(false)
    }

    /// Scrolls so `hour` is at the top. Scrolling while the grid is first
    /// laid out does nothing, so it waits for that to finish.
    private func scroll(_ proxy: ScrollViewProxy, to hour: Int) {
        Task {
            proxy.scrollTo(hour, anchor: .top)
        }
    }

    private func y(_ second: Int) -> CGFloat {
        HourGrid.y(second)
    }

    // MARK: Blocks

    private func blockView(_ block: DayBlock, dayIndex: Int, dayWidth: CGFloat, flagged: Bool) -> some View {
        let preview = drag.flatMap { $0.id == block.id ? $0 : nil }
        let startSecond = preview?.startSecond ?? block.startSecond
        let endSecond = preview?.endSecond ?? block.endSecond
        let shownDay = dayIndex + (preview?.dayShift ?? 0)
        let columnWidth = dayWidth / CGFloat(block.columns)
        let resolved = block.entry
        return TimelineBlock(
            title: model.ledger.projectTitle(resolved.entry.projectID),
            detail: TimelineBlock.detail(resolved, startSecond: startSecond, endSecond: endSecond, dragging: preview != nil),
            tags: resolved.entry.tags,
            links: model.ledger.issueLinks(tags: resolved.entry.tags, projectID: resolved.entry.projectID),
            color: model.ledger.color(ofProject: resolved.entry.projectID),
            flagged: flagged,
            selected: selection == block.id,
            running: resolved.isRunning
        )
        .frame(width: max(columnWidth - 3, 8), height: max(y(endSecond) - y(startSecond) - 2, 12))
        .overlay(alignment: .top) {
            ResizeHandle()
                .gesture(dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .start))
        }
        .overlay(alignment: .bottom) {
            if !resolved.isRunning {
                ResizeHandle()
                    .gesture(dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .end))
            }
        }
        .gesture(dragGesture(block, dayIndex: dayIndex, dayWidth: dayWidth, kind: .move))
        .onTapGesture {
            selection = block.id
        }
        .contextMenu {
            EntriesMenu(model: model, ids: [block.id], undoManager: undoManager, sheet: $sheet) { copies in
                selection = copies.first
            }
        }
        .offset(x: HourGrid.gutter + CGFloat(shownDay) * dayWidth + CGFloat(block.column) * columnWidth, y: y(startSecond))
    }

    // MARK: Editing

    private func dragGesture(_ block: DayBlock, dayIndex: Int, dayWidth: CGFloat, kind: HourGrid.DragKind) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !model.isReadOnly, kind != .move || !block.entry.isRunning else { return }
                let delta = Int((value.translation.height / HourGrid.hourHeight * 3600).rounded())
                let (start, end) = HourGrid.adjusted(block, kind: kind, by: delta)
                let shift = kind == .move
                    ? HourGrid.dayShift(value.translation.width, dayWidth: dayWidth, from: dayIndex, days: days.count)
                    : 0
                drag = DragState(id: block.id, kind: kind, startSecond: start, endSecond: end, dayShift: shift)
                selection = block.id
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

/// The strip along a block's top or bottom edge that drags its start or
/// end, with the resize pointer over it.
struct ResizeHandle: View {
    @State private var pushed = false

    var body: some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.resizeUpDown.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

#if DEBUG
#Preview("Day") {
    TimeGrid(
        model: PreviewData.model(),
        days: [LocalDate(year: 2026, month: 9, day: 22)],
        selection: .constant(PreviewData.entry("Call with Globex")),
        sheet: .constant(nil)
    )
    .frame(width: 700, height: 600)
}

#Preview("Week") {
    TimeGrid(
        model: PreviewData.model(),
        days: (21...27).map { LocalDate(year: 2026, month: 9, day: $0) },
        selection: .constant(nil),
        sheet: .constant(nil)
    )
    .frame(width: 1000, height: 600)
}
#endif
#endif
