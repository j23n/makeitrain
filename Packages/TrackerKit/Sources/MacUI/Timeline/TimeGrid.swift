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

    static let hourHeight: CGFloat = 60
    static let gutter: CGFloat = 58
    static let trailing: CGFloat = 12
    static let snap = 300
    /// The grid's coordinate space. Drags are measured in it rather than in
    /// the block's own, because the block moves under the pointer while
    /// it's dragged.
    static let space = "TimeGrid"

    enum DragKind {
        case move, start, end
    }

    struct DragState {
        var id: UUID
        var kind: DragKind
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
                scroll(proxy, to: Self.firstHour(columns))
            }
            .onChange(of: days) { _, newDays in
                let blocks = newDays.map { DayLayout.blocks(on: $0, entries: model.resolved, now: model.now) }
                scroll(proxy, to: Self.firstHour(blocks))
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
                let dayWidth = Self.dayWidth(geometry.size.width, days: days.count)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: dayWidth, height: Self.hourHeight * 24)
                            .onTapGesture(count: 2) { location in
                                addEntry(on: day, atY: location.y)
                            }
                            .offset(x: Self.gutter + CGFloat(index) * dayWidth)
                    }
                    ForEach(1..<max(days.count, 1), id: \.self) { index in
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: Self.hourHeight * 24)
                            .offset(x: Self.gutter + CGFloat(index) * dayWidth)
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
        .frame(height: Self.hourHeight * 24)
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
                        .frame(width: Self.gutter - 10, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Divider()
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: Self.hourHeight)
                .id(hour)
            }
        }
    }

    /// The week view's headings: each day's weekday, date and total. Click
    /// one to show that day.
    private func dayHeadings(columns: [[DayBlock]], today: LocalDate) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.gutter, height: 1)
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
                .frame(width: Self.trailing, height: 1)
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
            .offset(x: Self.gutter + CGFloat(dayIndex) * dayWidth, y: y(second))
            .allowsHitTesting(false)
    }

    /// The width of each day's column in a grid `width` points wide.
    static func dayWidth(_ width: CGFloat, days: Int) -> CGFloat {
        max((width - gutter - trailing) / CGFloat(max(days, 1)), 40)
    }

    /// The hour shown at the top unless an entry starts earlier.
    static let morning = 7

    /// The hour to scroll to: 7:00, or the hour of an entry that starts
    /// earlier.
    static func firstHour(_ columns: [[DayBlock]]) -> Int {
        min(columns.joined().map { $0.startSecond / 3600 }.min() ?? morning, morning)
    }

    /// Scrolls so `hour` is at the top. Scrolling while the grid is first
    /// laid out does nothing, so it waits for that to finish.
    private func scroll(_ proxy: ScrollViewProxy, to hour: Int) {
        Task {
            proxy.scrollTo(hour, anchor: .top)
        }
    }

    private func y(_ second: Int) -> CGFloat {
        CGFloat(second) / 3600 * Self.hourHeight
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
            detail: detail(resolved, startSecond: startSecond, endSecond: endSecond, dragging: preview != nil),
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
        .offset(x: Self.gutter + CGFloat(shownDay) * dayWidth + CGFloat(block.column) * columnWidth, y: y(startSecond))
    }

    private func detail(_ resolved: ResolvedEntry, startSecond: Int, endSecond: Int, dragging: Bool) -> String {
        let times: String
        if dragging {
            times = "\(Format.time(secondOfDay: startSecond)) – \(Format.time(secondOfDay: endSecond))"
        } else {
            let zone = resolved.entry.timeZone
            let end = resolved.end.map { Format.time($0, zone: zone) } ?? "now"
            times = "\(Format.time(resolved.start, zone: zone)) – \(end)"
        }
        return resolved.entry.note.isEmpty ? times : "\(times)  \(resolved.entry.note)"
    }

    // MARK: Editing

    private func dragGesture(_ block: DayBlock, dayIndex: Int, dayWidth: CGFloat, kind: DragKind) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !model.isReadOnly, kind != .move || !block.entry.isRunning else { return }
                let delta = Int((value.translation.height / Self.hourHeight * 3600).rounded())
                let (start, end) = Self.adjusted(block, kind: kind, by: delta)
                let shift = kind == .move
                    ? Self.dayShift(value.translation.width, dayWidth: dayWidth, from: dayIndex, days: days.count)
                    : 0
                drag = DragState(id: block.id, kind: kind, startSecond: start, endSecond: end, dayShift: shift)
                selection = block.id
            }
            .onEnded { _ in
                if let drag, drag.id == block.id, days.indices.contains(dayIndex) {
                    commit(drag, block, on: days[dayIndex])
                }
                drag = nil
            }
    }

    /// A block's start and end after dragging by `delta` seconds, snapped to
    /// five minutes and kept within the day.
    static func adjusted(_ block: DayBlock, kind: DragKind, by delta: Int) -> (Int, Int) {
        func snapped(_ second: Int) -> Int {
            Int((Double(second) / Double(snap)).rounded()) * snap
        }
        let length = block.endSecond - block.startSecond
        switch kind {
        case .move:
            let start = min(max(snapped(block.startSecond + delta), 0), max(86400 - length, 0))
            return (start, start + length)
        case .start:
            let start = min(max(snapped(block.startSecond + delta), 0), max(block.endSecond - snap, 0))
            return (start, block.endSecond)
        case .end:
            let end = max(min(snapped(block.endSecond + delta), 86400), block.startSecond + snap)
            return (block.startSecond, end)
        }
    }

    /// How many days a block dragged `width` points sideways moves: to the
    /// nearest day's column, within the days shown.
    static func dayShift(_ width: CGFloat, dayWidth: CGFloat, from index: Int, days: Int) -> Int {
        guard dayWidth > 0 else { return 0 }
        let shift = Int((width / dayWidth).rounded())
        return min(max(shift, -index), days - 1 - index)
    }

    private func commit(_ drag: DragState, _ block: DayBlock, on day: LocalDate) {
        let resolved = block.entry
        let zone = resolved.entry.timeZone
        func time(_ second: Int, on date: LocalDate) -> Timestamp {
            Timestamp(date: date, secondOfDay: second, zone: zone)
        }
        switch drag.kind {
        case .move:
            guard drag.startSecond != block.startSecond || drag.dayShift != 0 else { return }
            let shift = resolved.start.distance(to: time(drag.startSecond, on: day.adding(days: drag.dayShift)))
            model.updateEntries([block.id], actionName: "Move Entry", undoManager: undoManager) { entry in
                entry.start = entry.start.adding(milliseconds: shift)
                entry.end = entry.end.map { $0.adding(milliseconds: shift) }
            }
        case .start:
            guard drag.startSecond != block.startSecond else { return }
            if resolved.isRunning {
                model.setRunningStart(time(drag.startSecond, on: day), undoManager: undoManager)
            } else {
                model.updateEntries([block.id], actionName: "Change Start", undoManager: undoManager) {
                    $0.start = time(drag.startSecond, on: day)
                }
            }
        case .end:
            guard drag.endSecond != block.endSecond else { return }
            model.updateEntries([block.id], actionName: "Change End", undoManager: undoManager) {
                $0.end = time(drag.endSecond, on: day)
            }
        }
    }

    private func addEntry(on day: LocalDate, atY y: CGFloat) {
        guard !model.isReadOnly else { return }
        let second = min(max(Int(y / Self.hourHeight * 3600) / Self.snap * Self.snap, 0), 86400 - 3600)
        let zone = model.environment.timeZone()
        let entry = TimeEntry(
            start: Timestamp(date: day, secondOfDay: second, zone: zone),
            end: Timestamp(date: day, secondOfDay: second + 3600, zone: zone),
            timeZone: zone,
            updated: model.environment.now()
        )
        model.addEntry(entry, undoManager: undoManager)
        selection = entry.id
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

/// One entry's block: its project, times, note and tags, in the project's
/// color, with an orange edge when it overlaps another entry. Tags show when
/// the block has room for them; ones that refer to issues are tinted.
struct TimelineBlock: View {
    let title: String
    let detail: String
    var tags: [String] = []
    var links: [String: URL] = [:]
    let color: Color
    let flagged: Bool
    let selected: Bool
    let running: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(detailLines: 3, showsTags: true)
            content(detailLines: 1, showsTags: true)
            content(detailLines: 3, showsTags: false)
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(selected ? 0.42 : 0.22))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(flagged ? Color.orange : color)
                .frame(width: flagged ? 4 : 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? color : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
    }

    private func content(detailLines: Int, showsTags: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if flagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Overlaps another entry")
                }
                if running {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                }
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(detailLines)
            if showsTags, !tags.isEmpty {
                TagList(tags: tags, links: links, interactive: false, wraps: true)
                    .padding(.top, 2)
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
