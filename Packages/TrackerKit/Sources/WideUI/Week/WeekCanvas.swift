import SwiftUI
import TrackerCore
import TrackerKit

/// The hour grid: a column per day with its entries as blocks, and what
/// the suggested corrections would change drawn over them: changed times
/// struck through, parts that would be added as dashed outlines, time
/// counted twice hatched, and numbered markers.
struct WeekCanvas: View {
    let model: AppModel
    let week: WeekModel
    let days: [LocalDate]
    /// When a block is clicked, so the screen takes the keyboard back.
    let onSelect: () -> Void

    static let hourHeight: CGFloat = 56
    static let gutter: CGFloat = 52

    var body: some View {
        let layouts = days.map { DayLayout.blocks(on: $0, entries: week.entries(on: $0), now: model.now) }
        let hours = DayLayout.hours(
            blocks: layouts.joined(),
            additions: week.suggestedAdditions.map(\.entry),
            nowHour: days.contains(model.today) ? model.now.local(in: model.environment.timeZone()).hour : nil
        )
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter, height: 1)
                ForEach(days, id: \.self) { day in
                    DayHeading(model: model, week: week, day: day)
                }
            }
            .padding(.trailing, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.strongLine).frame(height: 1)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        HourGutter(hours: hours)
                        ForEach(days.indices, id: \.self) { index in
                            DayColumn(
                                model: model,
                                week: week,
                                days: days,
                                index: index,
                                blocks: layouts[index],
                                hours: hours,
                                onSelect: onSelect
                            )
                        }
                    }
                    .frame(height: CGFloat(hours.count) * Self.hourHeight)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .padding(.trailing, 10)
                    .background(alignment: .topLeading) {
                        // Anchors to scroll to: an hour's line each.
                        VStack(spacing: 0) {
                            ForEach(hours, id: \.self) { hour in
                                Color.clear.frame(height: Self.hourHeight).id(hour)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .onAppear {
                    proxy.scrollTo(max(hours.lowerBound, min(firstBusyHour(layouts), hours.upperBound - 1)), anchor: .top)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }

    /// The hour of the first entry, to scroll to.
    private func firstBusyHour(_ layouts: [[DayBlock]]) -> Int {
        layouts.joined().map { $0.startSecond / 3600 }.min() ?? 8
    }
}

/// A day's name, date and total over its column, with the total the
/// corrections would make struck through when that's different.
struct DayHeading: View {
    let model: AppModel
    let week: WeekModel
    let day: LocalDate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(spacing: 4) {
                Text(Format.weekday(day))
                    .fontWeight(.semibold)
                Text("\(day.day)")
                    .foregroundStyle(Theme.text2)
            }
            .foregroundStyle(day == model.today ? Theme.accent : Theme.text)
            Spacer(minLength: 4)
            let total = week.total(on: day)
            if let corrected = week.correctedTotal(on: day) {
                Text(Format.duration(total))
                    .font(.system(size: 11))
                    .strikethrough(true, color: Theme.amber)
                    .foregroundStyle(Theme.text3)
                Text(Format.duration(corrected))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
            } else if total > 0 {
                Text(Format.duration(total))
                    .font(.system(size: 12, weight: total > Corrections.longest ? .semibold : .regular))
                    .foregroundStyle(total > Corrections.longest ? Theme.amberText : Theme.text4)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The hours down the left.
struct HourGutter: View {
    let hours: Range<Int>

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(hours, id: \.self) { hour in
                Text(Format.hour(hour))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
                    .offset(y: max(0, CGFloat(hour - hours.lowerBound) * WeekCanvas.hourHeight - 7))
                    .padding(.trailing, 9)
            }
        }
        .frame(width: WeekCanvas.gutter, alignment: .topTrailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// What a drag on a block is doing.
struct BlockDrag {
    var id: UUID
    var kind: HourGrid.DragKind
    var translation: CGSize
}

/// One day's column: hour lines, blocks, what corrections would change,
/// and the current time.
struct DayColumn: View {
    let model: AppModel
    let week: WeekModel
    let days: [LocalDate]
    let index: Int
    let blocks: [DayBlock]
    let hours: Range<Int>
    let onSelect: () -> Void
    @State private var drag: BlockDrag?
    @State private var seamDrag: (id: String, offset: CGFloat)?
    @Environment(\.undoManager) private var undoManager

    private var day: LocalDate { days[index] }
    private let height = WeekCanvas.hourHeight

    /// The column's own coordinates, which drags measure in. A block's
    /// edges move while they're dragged, so a drag measured in the edge's
    /// coordinates would chase itself and jump back and forth.
    private static let space = "dayColumn"

    private func y(_ second: Int) -> CGFloat {
        (CGFloat(second) / 3600 - CGFloat(hours.lowerBound)) * height
    }

    private func y(_ time: Timestamp, zone: String) -> CGFloat {
        y(DayLayout.second(of: time, on: day, zone: zone))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                hourLines(width: width)
                continuations(width: width)
                ForEach(blocks) { block in
                    blockView(block, width: width)
                }
                ghosts(width: width)
                overlapBands(width: width)
                longEntryMarks(width: width)
                markers(width: width)
                nowLine(width: width)
            }
            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Format.longDay(day)))
    }

    // MARK: Grid

    private func hourLines(width: CGFloat) -> some View {
        ForEach(hours, id: \.self) { hour in
            Rectangle()
                .fill(Theme.hourLine)
                .frame(width: width, height: 1)
                .offset(y: y(hour * 3600))
        }
    }

    /// The part after midnight of an entry from the day before, as
    /// "–08:55 Thursday's Refactoring".
    @ViewBuilder
    private func continuations(width: CGFloat) -> some View {
        let before = week.entries(on: day.adding(days: -1)).filter { entry in
            guard let end = entry.end ?? (entry.isRunning ? model.now : nil) else { return false }
            return end.local(in: entry.entry.timeZone).date >= day
        }
        ForEach(before) { entry in
            let zone = entry.entry.timeZone
            let end = entry.end ?? model.now
            let endY = y(end, zone: zone)
            let tint = model.ledger.tint(ofProject: entry.entry.projectID)
            VStack(alignment: .leading, spacing: 1) {
                Text("–\(Format.time(end, zone: zone))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                Text("\(Format.weekday(entry.entry.day))'s \(model.ledger.title(of: entry.entry))")
                    .lineLimit(1)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text4)
            .padding(.horizontal, 8)
            .padding(.top, max(4, min(25, endY - 34)))
            .frame(width: width - 8, height: max(endY - y(hours.lowerBound * 3600), 20), alignment: .topLeading)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7).fill(tint.softFill))
            .overlay(alignment: .top) {
                Hatching().frame(height: min(19, max(endY, 0)))
            }
            .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7).strokeBorder(tint.ink.opacity(0.6)))
            .offset(x: 4, y: 0)
            .clipped()
            .onTapGesture {
                week.selectedEntry = entry.id
                onSelect()
            }
        }
    }

    // MARK: Blocks

    /// Where a block goes in a column `width` wide, from `start` to `end`
    /// seconds, moved sideways while it's dragged.
    private func frame(of block: DayBlock, start: Int, end: Int, width: CGFloat) -> CGRect {
        let columnWidth = (width - 8) / CGFloat(max(block.columns, 1))
        var dx: CGFloat = 0
        if let drag, drag.id == block.id, drag.kind == .move {
            dx = drag.translation.width
        }
        let top = y(start)
        let bottom = y(end)
        return CGRect(
            x: 4 + CGFloat(block.column) * columnWidth + dx,
            y: top,
            width: columnWidth - (block.columns > 1 ? 2 : 0),
            height: max(bottom - top, 18)
        )
    }

    private func blockView(_ block: DayBlock, width: CGFloat) -> some View {
        let (start, end) = dragTimes(block)
        let rect = frame(of: block, start: start, end: end, width: width)
        let entry = block.entry
        let selected = week.selectedEntry == entry.id
        return EntryBlock(
            model: model,
            entry: entry,
            startSecond: start,
            endSecond: end,
            height: rect.height,
            selected: selected,
            change: week.suggestedChange(of: entry.id),
            overnight: week.ranLongNote(for: entry)
        )
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .top) { edgeHandle(block, kind: .start, width: width) }
        .overlay(alignment: .bottom) { edgeHandle(block, kind: .end, width: width) }
        .offset(x: rect.minX, y: rect.minY)
        .zIndex(drag?.id == block.id ? 2 : (selected ? 1 : 0))
        .onTapGesture {
            week.selectedEntry = entry.id
            onSelect()
        }
        .gesture(dragGesture(block, kind: .move, width: width))
        .contextMenu { EntryMenu(model: model, entry: entry) }
    }

    /// A block's start and end, or where a drag on it puts them.
    private func dragTimes(_ block: DayBlock) -> (Int, Int) {
        guard let drag, drag.id == block.id else { return (block.startSecond, block.endSecond) }
        return HourGrid.adjusted(block, kind: drag.kind, by: Int(drag.translation.height / height * 3600))
    }

    /// Dragging a block to move it, or its top or bottom edge to change its
    /// start or end.
    private func dragGesture(_ block: DayBlock, kind: HourGrid.DragKind, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: kind == .move ? 4 : 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !model.isReadOnly else { return }
                drag = BlockDrag(id: block.id, kind: kind, translation: value.translation)
            }
            .onEnded { value in
                finishDrag(block, kind: kind, translation: value.translation, width: width)
            }
    }

    /// A thin strip along a block's top or bottom that drags its start or end.
    private func edgeHandle(_ block: DayBlock, kind: HourGrid.DragKind, width: CGFloat) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .resizeCursor()
            .gesture(dragGesture(block, kind: kind, width: width))
    }

    /// Applies a drag: a move goes to the day whose column it ends over,
    /// `width` being a column's width.
    private func finishDrag(_ block: DayBlock, kind: HourGrid.DragKind, translation: CGSize, width: CGFloat) {
        defer { drag = nil }
        guard !model.isReadOnly else { return }
        let (start, end) = HourGrid.adjusted(block, kind: kind, by: Int(translation.height / height * 3600))
        var shift = 0
        if kind == .move {
            let steps = HourGrid.dayShift(translation.width, dayWidth: width, from: index, days: days.count)
            shift = days[index + steps].daysSince1970 - day.daysSince1970
        }
        model.applyDrag(kind, to: block, on: day, startSecond: start, endSecond: end, dayShift: shift, undoManager: undoManager)
        week.selectedEntry = block.id
    }

    // MARK: Corrections

    /// What suggestions would add: logged events and parts of split entries.
    @ViewBuilder
    private func ghosts(width: CGFloat) -> some View {
        ForEach(week.suggestedAdditions.filter { $0.entry.day == day }) { addition in
            let entry = addition.entry
            let zone = entry.timeZone
            let top = y(entry.start, zone: zone)
            let bottom = y(entry.end ?? model.now, zone: zone)
            let times = Format.span(entry)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if addition.isEvent {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.text3)
                        Text(times)
                            .foregroundStyle(Theme.text3)
                    } else {
                        Text(times)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amberText)
                        Spacer(minLength: 2)
                        Text("+ new")
                            .foregroundStyle(Theme.amberText)
                    }
                }
                .font(.system(size: 10.5))
                .monospacedDigit()
                Text(model.ledger.title(of: entry))
                    .font(.system(size: 11.5, weight: addition.isEvent ? .regular : .semibold))
                    .foregroundStyle(Theme.text4)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width - 8, height: max(bottom - top, 22), alignment: .topLeading)
            .background {
                if !addition.isEvent {
                    RoundedRectangle(cornerRadius: 7).fill(model.ledger.tint(ofProject: entry.projectID).fill)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(addition.isEvent ? Theme.ghost : Theme.amber, style: StrokeStyle(lineWidth: addition.isEvent ? 1 : 1.5, dash: [4, 3]))
            )
            .clipped()
            .offset(x: 4, y: top)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Suggested: \(entry.note), \(times)"))
        }
    }

    /// Time two entries both count, hatched, with a handle to drag the
    /// seam between them where there's one to move.
    @ViewBuilder
    private func overlapBands(width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            if case let .overlap(overlap) = preview.correction.kind,
               let span = model.ledger.doubleCountedSpan(overlap, running: model.running?.id, now: model.now),
               let earlier = model.ledger.entries[overlap.earlier], let later = model.ledger.entries[overlap.later] {
                let zone = later.timeZone
                let top = y(span.start, zone: zone)
                let bottom = y(span.end, zone: zone)
                let offset = seamDrag?.id == preview.id ? seamDrag?.offset ?? 0 : 0
                ZStack {
                    Hatching()
                        .frame(height: max(bottom - top, 3))
                        .overlay(alignment: .top) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                        .allowsHitTesting(false)
                    if model.ledger.canMoveSeam(earlier: earlier.id, later: later.id) {
                        Text("⇕ seam")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.markerText)
                            .padding(.horizontal, 8)
                            .frame(height: 21)
                            .background(Capsule().fill(Theme.marker))
                            .offset(y: offset)
                            .resizeCursor()
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                                    .onChanged { value in
                                        seamDrag = (preview.id, value.translation.height)
                                    }
                                    .onEnded { value in
                                        seamDrag = nil
                                        let seconds = Int64(value.translation.height / height * 3600) * 1000
                                        let middle = span.start.adding(milliseconds: span.duration / 2)
                                        let seam = middle.adding(milliseconds: seconds).rounded(toMinutes: 5)
                                        model.moveSeam(earlier: earlier.id, later: later.id, to: seam, undoManager: undoManager)
                                    }
                            )
                            .help("Drag to move where \(model.ledger.title(of: earlier)) ends and \(model.ledger.title(of: later)) starts")
                            .accessibilityLabel(Text("Drag the seam between \(model.ledger.title(of: earlier)) and \(model.ledger.title(of: later))"))
                    }
                }
                .frame(width: width - 8, height: max(bottom - top, 3))
                .offset(x: 4, y: top)
                .zIndex(3)
            }
        }
    }

    /// Where an entry that ran long likely ended: a dashed line with the
    /// suggested time, and the rest hatched.
    @ViewBuilder
    private func longEntryMarks(width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            if case let .ranLong(id, _) = preview.correction.kind, let entry = model.ledger.entries[id],
               case let .end(_, suggested)? = preview.correction.suggestion {
                let zone = entry.timeZone
                let line = y(suggested, zone: zone)
                let bottom = y(entry.end ?? model.now, zone: zone)
                ZStack(alignment: .topTrailing) {
                    Hatching()
                        .frame(height: max(bottom - line, 0))
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle()
                        .fill(Theme.amber)
                        .frame(height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Text("\(Format.time(suggested, zone: zone))?")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.markerText)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(Capsule().fill(Theme.marker))
                        .offset(x: -4, y: -10)
                }
                .frame(width: width - 8, height: max(bottom - line, 22), alignment: .top)
                .offset(x: 4, y: line)
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
    }

    /// The corrections' numbers, at the top right of what they're about.
    @ViewBuilder
    private func markers(width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            let top = markerTop(preview)
            CorrectionMarker(preview.number)
                .background(Circle().strokeBorder(Theme.canvas, lineWidth: 2).padding(-2))
                .offset(x: width - 18, y: max(top - 8, 0))
                .zIndex(4)
                .onTapGesture {
                    week.selectedEntry = nil
                    week.selectedCorrection = preview.id
                }
        }
    }

    private func markerTop(_ preview: CorrectionPreview) -> CGFloat {
        switch preview.correction.kind {
        case let .overlap(overlap):
            let entry = model.ledger.entries[overlap.earlier]
            let later = model.ledger.entries[overlap.later]
            if let entry, let later, entry.day == day {
                return min(y(entry.start, zone: entry.timeZone), y(later.start, zone: later.timeZone))
            }
            return later.map { y($0.start, zone: $0.timeZone) } ?? 0
        case let .ranLong(id, _), let .noProject(id):
            return model.ledger.entries[id].map { y($0.start, zone: $0.timeZone) } ?? 0
        case let .notLogged(entry):
            return y(entry.start, zone: entry.timeZone)
        }
    }

    /// The red line at the current time, on today.
    @ViewBuilder
    private func nowLine(width: CGFloat) -> some View {
        if day == model.today {
            let top = y(model.now, zone: model.environment.timeZone())
            HStack(spacing: 0) {
                Circle().fill(Theme.now).frame(width: 7, height: 7)
                Rectangle().fill(Theme.now).frame(height: 1.5)
            }
            .frame(width: width + 3)
            .offset(x: -3, y: top - 3.5)
            .allowsHitTesting(false)
            .zIndex(5)
        }
    }
}

/// One entry on the grid: its times, title and tags in its project's tint,
/// selected with an outline, changed by a suggestion with a dashed amber
/// edge and the times it would get.
struct EntryBlock: View {
    let model: AppModel
    let entry: ResolvedEntry
    let startSecond: Int
    let endSecond: Int
    let height: CGFloat
    let selected: Bool
    let change: (before: TimeEntry, after: TimeEntry)?
    let overnight: String?

    private var unassigned: Bool { entry.entry.projectID == nil }
    private var tint: ProjectTint { model.ledger.tint(ofProject: entry.entry.projectID) }
    private var zone: String { entry.entry.timeZone }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, height < 34 ? 0 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height < 34 ? .leading : .topLeading)
            .background(RoundedRectangle(cornerRadius: 7).fill(fill))
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if unassigned { return Theme.fill }
        return selected || entry.isRunning ? tint.strongFill : tint.fill
    }

    @ViewBuilder
    private var border: some View {
        if selected {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.selection, lineWidth: 2)
        } else if change != nil {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.amber, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        } else if unassigned {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.ghost, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            RoundedRectangle(cornerRadius: 7).strokeBorder(tint.ink, lineWidth: 1)
        }
    }

    private var title: String {
        model.ledger.title(of: entry.entry)
    }

    @ViewBuilder
    private var content: some View {
        if height < 34 {
            HStack(spacing: 6) {
                if unassigned {
                    Circle().strokeBorder(Theme.text3, lineWidth: 1.5).frame(width: 8, height: 8)
                }
                Text(Format.time(secondOfDay: startSecond))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text4)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                times
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(height > 60 ? 2 : 1)
                if !entry.entry.tags.isEmpty, height > 52 {
                    Text(entry.entry.tags.joined(separator: " "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tag)
                        .lineLimit(1)
                }
                if let overnight, height > 70 {
                    Text(overnight)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.amberFill))
                        .padding(.top, 4)
                }
            }
        }
    }

    /// "09:30–12:30", or with a suggestion "09:00–12:40 11:00", the old end
    /// struck through.
    private var times: some View {
        HStack(spacing: 3) {
            if let change {
                let startChanged = change.before.start != change.after.start
                let endChanged = change.before.end != change.after.end
                ChangedText(old: startChanged ? Format.time(change.before.start, zone: zone) : nil, new: Format.time(change.after.start, zone: zone), size: 10.5)
                Text("–")
                ChangedText(
                    old: endChanged ? change.before.end.map { Format.time($0, zone: zone) } ?? "now" : nil,
                    new: change.after.end.map { Format.time($0, zone: zone) } ?? "now",
                    size: 10.5
                )
            } else {
                Text(Format.time(secondOfDay: startSecond) + "–" + (entry.isRunning ? "now" : Format.time(secondOfDay: min(endSecond, 86399))))
            }
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(Theme.text4)
        .lineLimit(1)
    }
}

/// What an entry's context menu offers, on the week and on the iPhone's
/// day: stopping or continuing it, its project, splitting, duplicating and
/// deleting it. With `touch`, as on the iPhone, the items have icons.
public struct EntryMenu: View {
    let model: AppModel
    let entry: ResolvedEntry
    let touch: Bool
    @Environment(\.undoManager) private var undoManager

    public init(model: AppModel, entry: ResolvedEntry, touch: Bool = false) {
        self.model = model
        self.entry = entry
        self.touch = touch
    }

    public var body: some View {
        if entry.isRunning {
            item("Stop", "stop.fill") {
                model.stopTimer(undoManager: undoManager)
            }
        } else {
            item("Continue", "play.fill") {
                model.continueEntry(entry, undoManager: undoManager)
            }
        }
        Menu("Project") {
            ForEach(model.ledger.pickerProjects()) { project in
                Button(model.ledger.projectTitle(project.id)) {
                    model.updateEntry(entry.id, actionName: "Set Project", undoManager: undoManager) { $0.projectID = project.id }
                }
            }
            Divider()
            Button("Unassigned") {
                model.updateEntry(entry.id, actionName: "Set Project", undoManager: undoManager) { $0.projectID = nil }
            }
        }
        if EntrySplit.time(for: entry, now: model.now) != nil {
            item("Split in the Middle", "scissors") {
                model.splitInMiddle(entry, undoManager: undoManager)
            }
        }
        if !entry.isRunning {
            item("Duplicate", "plus.square.on.square") {
                model.duplicateEntry(entry.id, undoManager: undoManager)
            }
        }
        Divider()
        item("Delete", "trash", role: .destructive) {
            model.deleteEntry(entry.id, undoManager: undoManager)
        }
    }

    /// An item, with its icon on a touch screen.
    @ViewBuilder
    private func item(_ title: LocalizedStringKey, _ systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        if touch {
            Button(title, systemImage: systemImage, role: role, action: action)
        } else {
            Button(title, role: role, action: action)
        }
    }
}
