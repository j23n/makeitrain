#if os(macOS)
import AppKit
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
    var onSelect: () -> Void = {}

    static let hourHeight: CGFloat = 56
    static let gutter: CGFloat = 52

    var body: some View {
        let layouts = days.map { DayLayout.blocks(on: $0, entries: week.entries(on: $0), now: model.now) }
        let hours = hourRange(layouts)
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

    /// The hours shown: 7:00 to 19:00, widened to any entry, ghost or the
    /// current time.
    private func hourRange(_ layouts: [[DayBlock]]) -> Range<Int> {
        var first = 7
        var last = 19
        for block in layouts.joined() {
            first = min(first, block.startSecond / 3600)
            last = max(last, Int((Double(block.endSecond) / 3600).rounded(.up)))
        }
        for addition in week.suggestedAdditions {
            let zone = addition.entry.timeZone
            first = min(first, addition.entry.start.local(in: zone).hour)
            if let end = addition.entry.end {
                last = max(last, end.local(in: zone).hour + 1)
            }
        }
        if days.contains(model.today) {
            let hour = model.now.local(in: model.environment.timeZone()).hour
            first = min(first, hour)
            last = max(last, hour + 1)
        }
        return max(0, first)..<min(24, max(last, first + 1))
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
struct BlockDrag: Equatable {
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

    private func y(_ second: Int) -> CGFloat {
        (CGFloat(second) / 3600 - CGFloat(hours.lowerBound)) * height
    }

    private func y(_ time: Timestamp, zone: String) -> CGFloat {
        let local = time.local(in: zone)
        let second = local.date == day ? local.millisecondOfDay / 1000 : (local.date < day ? 0 : 86400)
        return y(second)
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
                Text("\(Format.weekday(entry.entry.day))'s \(title(of: entry.entry))")
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

    private func frame(of block: DayBlock, width: CGFloat) -> CGRect {
        let columnWidth = (width - 8) / CGFloat(max(block.columns, 1))
        var start = block.startSecond
        var end = block.endSecond
        var dx: CGFloat = 0
        if let drag, drag.id == block.id {
            let delta = Int(drag.translation.height / height * 3600)
            (start, end) = HourGrid.adjusted(block, kind: drag.kind, by: delta)
            if drag.kind == .move {
                dx = drag.translation.width
            }
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
        let rect = frame(of: block, width: width)
        let entry = block.entry
        let selected = week.selectedEntry == entry.id
        let change = week.suggestedChange(of: entry.id)
        return EntryBlock(
            model: model,
            entry: entry,
            startSecond: dragTimes(block).0,
            endSecond: dragTimes(block).1,
            height: rect.height,
            selected: selected,
            change: change.map { ($0.before, $0.after) },
            overnight: overnightNote(entry)
        )
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .top) { edgeHandle(block, kind: .start) }
        .overlay(alignment: .bottom) { edgeHandle(block, kind: .end) }
        .offset(x: rect.minX, y: rect.minY)
        .zIndex(drag?.id == block.id ? 2 : (selected ? 1 : 0))
        .onTapGesture {
            week.selectedEntry = entry.id
            onSelect()
        }
        .gesture(moveGesture(block, width: width))
        .contextMenu { EntryMenu(model: model, entry: entry) }
    }

    private func dragTimes(_ block: DayBlock) -> (Int, Int) {
        guard let drag, drag.id == block.id else { return (block.startSecond, block.endSecond) }
        return HourGrid.adjusted(block, kind: drag.kind, by: Int(drag.translation.height / height * 3600))
    }

    private func moveGesture(_ block: DayBlock, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !model.isReadOnly else { return }
                drag = BlockDrag(id: block.id, kind: .move, translation: value.translation)
            }
            .onEnded { value in
                finishDrag(block, kind: .move, translation: value.translation, width: width)
            }
    }

    /// A thin strip along a block's top or bottom that drags its start or end.
    private func edgeHandle(_ block: DayBlock, kind: HourGrid.DragKind) -> some View {
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
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard !model.isReadOnly else { return }
                        drag = BlockDrag(id: block.id, kind: kind, translation: CGSize(width: 0, height: value.translation.height))
                    }
                    .onEnded { value in
                        finishDrag(block, kind: kind, translation: CGSize(width: 0, height: value.translation.height), width: 0)
                    }
            )
    }

    /// Applies a drag: a move goes to the day whose column it ends over,
    /// `width` being a column's width.
    private func finishDrag(_ block: DayBlock, kind: HourGrid.DragKind, translation: CGSize, width: CGFloat) {
        defer { drag = nil }
        guard !model.isReadOnly else { return }
        let (start, end) = HourGrid.adjusted(block, kind: kind, by: Int(translation.height / height * 3600))
        var shift = 0
        if kind == .move, width > 0 {
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
            let times = "\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
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
                Text(entry.note.isEmpty ? model.ledger.projectTitle(entry.projectID) : entry.note)
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
    /// seam between them.
    @ViewBuilder
    private func overlapBands(width: CGFloat) -> some View {
        ForEach(week.previews.filter { $0.correction.day == day }) { preview in
            if case let .overlap(overlap) = preview.correction.kind,
               let earlier = model.ledger.entries[overlap.earlier], let later = model.ledger.entries[overlap.later],
               let earlierEnd = earlier.end, later.end.map({ earlierEnd <= $0 }) ?? true {
                let zone = later.timeZone
                let top = y(later.start, zone: zone)
                let bottom = y(earlierEnd, zone: zone)
                let offset = seamDrag?.id == preview.id ? seamDrag?.offset ?? 0 : 0
                ZStack {
                    Hatching()
                        .frame(height: max(bottom - top, 3))
                        .overlay(alignment: .top) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.amber).frame(height: 1.5) }
                        .allowsHitTesting(false)
                    Text("⇕ seam")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.markerText)
                        .padding(.horizontal, 8)
                        .frame(height: 21)
                        .background(Capsule().fill(Theme.marker))
                        .offset(y: offset)
                        .onHover { inside in
                            if inside {
                                NSCursor.resizeUpDown.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    seamDrag = (preview.id, value.translation.height)
                                }
                                .onEnded { value in
                                    seamDrag = nil
                                    let seconds = Int64(value.translation.height / height * 3600) * 1000
                                    let middle = later.start.adding(milliseconds: later.start.distance(to: earlierEnd) / 2)
                                    let snapped = Timestamp(milliseconds: (middle.milliseconds + seconds + 150_000) / 300_000 * 300_000)
                                    model.moveSeam(earlier: earlier.id, later: later.id, to: snapped, undoManager: undoManager)
                                }
                        )
                        .help("Drag to move where \(title(of: earlier)) ends and \(title(of: later)) starts")
                        .accessibilityLabel(Text("Drag the seam between \(title(of: earlier)) and \(title(of: later))"))
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
                        .offset(y: 0)
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

    /// "ran overnight · 19:25" on a block that did.
    private func overnightNote(_ entry: ResolvedEntry) -> String? {
        for preview in week.previews {
            if case let .ranLong(id, overnight) = preview.correction.kind, id == entry.id {
                let length = Format.duration(model.duration(of: entry))
                if entry.isRunning { return "running \(length)" }
                return overnight ? "ran overnight · \(length)" : "ran \(length)"
            }
        }
        return nil
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

    private func title(of entry: TimeEntry) -> String {
        entry.note.isEmpty ? model.ledger.projectTitle(entry.projectID) : entry.note
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
        if !entry.entry.note.isEmpty { return entry.entry.note }
        return model.ledger.projectTitle(entry.entry.projectID)
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

/// What a block's context menu offers.
struct EntryMenu: View {
    let model: AppModel
    let entry: ResolvedEntry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if entry.isRunning {
            Button("Stop") {
                model.stopTimer(undoManager: undoManager)
            }
        }
        Menu("Project") {
            ForEach(model.ledger.pickerProjects()) { project in
                Button(model.ledger.projectTitle(project.id)) {
                    model.updateEntries([entry.id], actionName: "Set Project", undoManager: undoManager) { $0.projectID = project.id }
                }
            }
            Divider()
            Button("Unassigned") {
                model.updateEntries([entry.id], actionName: "Set Project", undoManager: undoManager) { $0.projectID = nil }
            }
        }
        if EntrySplit.range(of: entry, now: model.now) != nil {
            Button("Split in the Middle") {
                model.splitEntry(entry.id, at: Timestamp(EntrySplit.suggestedTime(for: entry, now: model.now)), undoManager: undoManager)
            }
        }
        if !entry.isRunning {
            Button("Duplicate") {
                model.duplicateEntries([entry.id], undoManager: undoManager)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            model.deleteEntries([entry.id], undoManager: undoManager)
        }
    }
}
#endif
