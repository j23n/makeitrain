#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// A day's entries as blocks on a timeline, with an inspector for the
/// selected one.
struct DayTimelineScreen: View {
    let model: AppModel
    /// The day shown, or nil for today.
    @State private var day: LocalDate?
    @State private var selection: UUID?
    @State private var showInspector = true

    private var shownDay: LocalDate { day ?? model.today }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            DayTimeline(model: model, day: shownDay, selection: $selection)
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
            EntryInspector(model: model, ids: selection.map { Set([$0]) } ?? [])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ControlGroup {
                Button {
                    day = shownDay.adding(days: -1)
                } label: {
                    Label("Previous Day", systemImage: "chevron.left")
                }
                Button("Today") {
                    day = nil
                }
                Button {
                    day = shownDay.adding(days: 1)
                } label: {
                    Label("Next Day", systemImage: "chevron.right")
                }
            }
            .fixedSize()
            Text(Format.days(shownDay...shownDay))
                .font(.headline)
            Spacer()
            Text("\(Format.duration(dayTotal)) logged")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            DatePicker(
                "Day",
                selection: Binding(
                    get: { shownDay.pickerDate },
                    set: { date in
                        let picked = LocalDate(pickerDate: date)
                        day = picked == model.today ? nil : picked
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dayTotal: Int64 {
        model.resolved
            .filter { $0.entry.day == shownDay }
            .reduce(0) { $0 + model.duration(of: $1) }
    }
}

/// The blocks of one day, drawn at their own wall-clock time. Drag a block
/// to move it, drag its top or bottom edge to change its start or end, and
/// double-click empty space to add an hour. Times snap to five minutes.
struct DayTimeline: View {
    let model: AppModel
    let day: LocalDate
    @Binding var selection: UUID?
    @Environment(\.undoManager) private var undoManager
    @State private var drag: DragState?

    static let hourHeight: CGFloat = 60
    static let gutter: CGFloat = 58
    static let snap = 300

    enum DragKind {
        case move, start, end
    }

    struct DragState {
        var id: UUID
        var kind: DragKind
        var startSecond: Int
        var endSecond: Int
    }

    var body: some View {
        let blocks = DayLayout.blocks(on: day, entries: model.resolved, now: model.now)
        let flagged = model.overlaps.flagged
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    GeometryReader { geometry in
                        let width = max(geometry.size.width - Self.gutter - 12, 40)
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { location in
                                    addEntry(atY: location.y)
                                }
                            ForEach(blocks) { block in
                                blockView(block, width: width, flagged: flagged.contains(block.id))
                            }
                            if day == model.today {
                                nowLine(width: width)
                            }
                        }
                    }
                }
                .frame(height: Self.hourHeight * 24)
                .padding(.vertical, 10)
            }
            .onAppear {
                proxy.scrollTo(firstHour(blocks), anchor: .top)
            }
            .onChange(of: day) { _, _ in
                proxy.scrollTo(firstHour(DayLayout.blocks(on: day, entries: model.resolved, now: model.now)), anchor: .top)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand {
            guard let selection else { return }
            model.deleteEntries([selection], undoManager: undoManager)
        }
        .overlay(alignment: .bottom) {
            if blocks.isEmpty {
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

    private var hourGrid: some View {
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

    private func nowLine(width: CGFloat) -> some View {
        let second = model.now.local(in: TimeZone.current.identifier).millisecondOfDay / 1000
        return Rectangle()
            .fill(Color.red)
            .frame(width: width + 8, height: 1.5)
            .offset(x: Self.gutter - 4, y: y(second))
            .allowsHitTesting(false)
    }

    /// The hour to scroll to: just before the first entry, or 8 AM.
    private func firstHour(_ blocks: [DayBlock]) -> Int {
        blocks.first.map { max(0, $0.startSecond / 3600 - 1) } ?? 8
    }

    private func y(_ second: Int) -> CGFloat {
        CGFloat(second) / 3600 * Self.hourHeight
    }

    // MARK: Blocks

    private func blockView(_ block: DayBlock, width: CGFloat, flagged: Bool) -> some View {
        let preview = drag.flatMap { $0.id == block.id ? $0 : nil }
        let startSecond = preview?.startSecond ?? block.startSecond
        let endSecond = preview?.endSecond ?? block.endSecond
        let columnWidth = width / CGFloat(block.columns)
        let resolved = block.entry
        return TimelineBlock(
            title: model.ledger.projectTitle(resolved.entry.projectID),
            detail: detail(resolved, startSecond: startSecond, endSecond: endSecond, dragging: preview != nil),
            color: model.ledger.color(ofProject: resolved.entry.projectID),
            flagged: flagged,
            selected: selection == block.id,
            running: resolved.isRunning
        )
        .frame(width: max(columnWidth - 3, 8), height: max(y(endSecond) - y(startSecond) - 2, 12))
        .overlay(alignment: .top) {
            edgeHandle(block, kind: .start)
        }
        .overlay(alignment: .bottom) {
            if !resolved.isRunning {
                edgeHandle(block, kind: .end)
            }
        }
        .gesture(dragGesture(block, kind: .move))
        .onTapGesture {
            selection = block.id
        }
        .contextMenu {
            Button("Delete Entry", role: .destructive) {
                model.deleteEntries([block.id], undoManager: undoManager)
            }
        }
        .offset(x: Self.gutter + CGFloat(block.column) * columnWidth, y: y(startSecond))
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

    private func edgeHandle(_ block: DayBlock, kind: DragKind) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(dragGesture(block, kind: kind))
    }

    // MARK: Editing

    private func dragGesture(_ block: DayBlock, kind: DragKind) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !model.isReadOnly, kind != .move || !block.entry.isRunning else { return }
                let delta = Int((value.translation.height / Self.hourHeight * 3600).rounded())
                let (start, end) = Self.adjusted(block, kind: kind, by: delta)
                drag = DragState(id: block.id, kind: kind, startSecond: start, endSecond: end)
                selection = block.id
            }
            .onEnded { _ in
                if let drag, drag.id == block.id {
                    commit(drag, block)
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

    private func commit(_ drag: DragState, _ block: DayBlock) {
        let resolved = block.entry
        let zone = resolved.entry.timeZone
        func time(_ second: Int) -> Timestamp {
            Timestamp(date: day, secondOfDay: second, zone: zone)
        }
        switch drag.kind {
        case .move:
            guard drag.startSecond != block.startSecond else { return }
            let shift = resolved.start.distance(to: time(drag.startSecond))
            model.updateEntries([block.id], actionName: "Move Entry", undoManager: undoManager) { entry in
                entry.start = entry.start.adding(milliseconds: shift)
                entry.end = entry.end.map { $0.adding(milliseconds: shift) }
            }
        case .start:
            guard drag.startSecond != block.startSecond else { return }
            if resolved.isRunning {
                model.setRunningStart(time(drag.startSecond), undoManager: undoManager)
            } else {
                model.updateEntries([block.id], actionName: "Change Start", undoManager: undoManager) { $0.start = time(drag.startSecond) }
            }
        case .end:
            guard drag.endSecond != block.endSecond else { return }
            model.updateEntries([block.id], actionName: "Change End", undoManager: undoManager) { $0.end = time(drag.endSecond) }
        }
    }

    private func addEntry(atY y: CGFloat) {
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

/// One entry's block: its project, times and note, in the project's color,
/// with an orange edge when it overlaps another entry.
struct TimelineBlock: View {
    let title: String
    let detail: String
    let color: Color
    let flagged: Bool
    let selected: Bool
    let running: Bool

    var body: some View {
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
                .lineLimit(3)
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
}
#endif
